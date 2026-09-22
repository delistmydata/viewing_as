require "json"

module ViewingAs
  # The controller side. Include it AFTER the callback that loads the sign-in
  # state, because the guards below assume it has run:
  #
  #   class ApplicationController < ActionController::Base
  #     include Authentication
  #     include ViewingAs::Controller
  #   end
  #
  # Registration order, top to bottom, is load-bearing:
  #
  #   resume_impersonation ..... re-derives the viewing state from the cookie
  #       and the database, on every request, before anything renders. Also
  #       where the page-view row is logged: deliberately before the
  #       around_action that forbids writes.
  #   refuse_writes ............ the policy: no non-GET while viewing read-only.
  #   read_only ................ the guarantee, for whatever the policy cannot see.
  #   no_store ................. so no cache between here and the browser keeps
  #       a page rendered for one named person.
  module Controller
    extend ActiveSupport::Concern

    # What #impersonate returns.
    Attempt = Data.define(:started, :reason) do
      def started? = started
    end

    included do
      before_action :resume_impersonation
      before_action :refuse_writes_while_impersonating
      around_action :read_only_while_impersonating
      after_action :no_store_while_impersonating

      if respond_to?(:helper_method)
        helper_method :true_user, :impersonated_user, :impersonating?,
                      :impersonation_expires_at, :impersonation_read_only?
      end
    end

    private

    # Who is actually here. Every permission check and every log row uses this;
    # using the acting user for either would let a viewed request authorise
    # itself as the account owner, or file the admin's reads under the owner's
    # own name.
    def true_user
      ViewingAs.config.true_user.call(self)
    end

    # Who this request acts as, when someone is viewing; nil otherwise.
    def impersonated_user
      ViewingAs::Current.impersonated_user
    end

    def impersonating?
      ViewingAs::Current.impersonating?
    end

    def impersonation_expires_at
      ViewingAs::Current.expires_at
    end

    def impersonation_read_only?
      impersonating? && ViewingAs::Current.read_only == true
    end

    # Starts viewing `target`, or refuses and says why. Both outcomes are
    # logged. Returns an Attempt: check #started? and read #reason.
    #
    # read_only: nil takes the configured default. Pass false to start a
    # session that may write; the choice is sealed into the signed cookie, so
    # it cannot be changed from the browser once made, and recorded on the
    # start row so the log says which kind of session it was.
    def impersonate(target, read_only: nil)
      admin = true_user

      unless admin && ViewingAs.config.may_impersonate.call(admin)
        return refuse_impersonation(admin, target, "You are not permitted to view other accounts.")
      end
      return refuse_impersonation(admin, target, "You cannot view your own account this way.") if target == admin
      if (reason = ViewingAs.config.refusal_for(target, admin))
        return refuse_impersonation(admin, target, reason)
      end

      begin_impersonation!(target, read_only: read_only)
      record_viewing_event(admin, target, Kinds::START,
                           detail: (impersonation_read_only? ? nil : "writable"))
      Attempt.new(started: true, reason: nil)
    end

    # Ends the current viewing session, logging `kind`. Safe to call when
    # nothing is being viewed.
    def end_impersonation!(kind = Kinds::STOP, subject = nil)
      subject ||= ViewingAs.config.find_target.call(impersonation_payload&.dig("user_id"))
      cookies.delete(ViewingAs.config.cookie_name)
      ViewingAs::Current.impersonated_user = nil
      ViewingAs::Current.expires_at = nil
      ViewingAs::Current.read_only = nil

      record_viewing_event(true_user, subject, kind)
      nil
    end

    # Mints the cookie and sets the state, with no checks and no log row.
    # #impersonate is the front door; this is here for hosts that have already
    # decided.
    def begin_impersonation!(target, read_only: nil)
      read_only = ViewingAs.config.read_only if read_only.nil?
      started_at = Time.current

      cookies.signed[ViewingAs.config.cookie_name] = {
        value: { admin_session_id: ViewingAs.config.session_id.call(self),
                 user_id: target.id,
                 started_at: started_at.to_i,
                 read_only: read_only }.to_json,
        httponly: true,
        same_site: :lax,
        secure: ViewingAs.config.secure_cookie.call
        # Deliberately NO expires. The timeout is enforced server-side off
        # started_at, and a cookie carrying the same lifetime would simply
        # vanish from the browser first, so the expiry would never be seen here
        # and never written to the log, leaving the account owner a session
        # that started and apparently never ended.
      }

      ViewingAs::Current.impersonated_user = target
      ViewingAs::Current.expires_at = started_at + ViewingAs.config.timeout
      ViewingAs::Current.read_only = read_only
    end

    # Re-derived from scratch on every request rather than trusted from the
    # cookie we minted. That is the whole design: consent withdrawn, an admin
    # flag revoked, an account closed and a sign-out elsewhere all take effect
    # on the very next click, without reaching into anybody's browser.
    def resume_impersonation
      payload = impersonation_payload
      return if payload.nil?

      ViewingAs.config.resume_session.call(self)
      admin = true_user
      target = ViewingAs.config.find_target.call(payload["user_id"])
      started_at = payload["started_at"].to_i

      if started_at < ViewingAs.config.timeout.ago.to_i
        return finish_impersonation(Kinds::EXPIRED, target)
      end

      unless admin && ViewingAs.config.may_impersonate.call(admin) &&
             ViewingAs.config.session_id.call(self) == payload["admin_session_id"]
        return finish_impersonation(Kinds::REVOKED, target)
      end

      unless target && target != admin && ViewingAs.config.refusal_for(target, admin).nil?
        return finish_impersonation(Kinds::REVOKED, target)
      end

      ViewingAs::Current.impersonated_user = target
      ViewingAs::Current.expires_at = at(started_at) + ViewingAs.config.timeout
      ViewingAs::Current.read_only = payload.key?("read_only") ? payload["read_only"] : ViewingAs.config.read_only

      record_viewing_event(admin, target, Kinds::READ)
    end

    # Ends a session that has stopped being valid, and refuses the request if
    # it was going to write.
    #
    # The refusal is the whole point. Without it the filter chain simply
    # carries on: nothing is being viewed any more, so the write guard waves
    # the request through, and the acting user has silently become the ADMIN.
    # A click aimed at somebody else's account would land on the admin's own.
    # The only honest answer is not to do it to theirs. This holds in writable
    # sessions too; it is about whose account the click lands on, not about
    # whether writes were allowed.
    #
    # Nobody signed in means nobody's account to land on: a sign-in POST made
    # while holding a dead cookie is the visitor's own, and goes through.
    def finish_impersonation(kind, subject)
      end_impersonation!(kind, subject)
      return if request.env["REQUEST_METHOD"].in?(%w[ GET HEAD ])
      return if true_user.nil?

      render plain: "That session ended before this went through. Nothing was changed.",
             status: :conflict
    end

    # The policy: reads only.
    #
    # Read straight off the Rack env, the same method the router dispatched
    # on. Rack::MethodOverride resolves _method and X-Http-Method-Override
    # before either runs, so there is no spelling of a request that routes to
    # a write action while presenting here as a GET.
    def refuse_writes_while_impersonating
      return unless impersonation_read_only? && ViewingAs.config.read_only_layer?(:policy)
      return if request.env["REQUEST_METHOD"].in?(%w[ GET HEAD ])

      render plain: "Read-only while viewing another account.", status: :forbidden
    end

    # The guarantee, for everything the policy above cannot see: an
    # update_column in a helper, a counter cache, a touch-on-read added later.
    # Reaching this is a bug rather than a user action, which is why it logs
    # at error.
    #
    # Covers ActiveRecord only. A GET that enqueued a job, sent mail or wrote
    # to S3 would still fire; a spec asserting no job is enqueued during a
    # viewed GET is what keeps that true.
    def read_only_while_impersonating
      return yield unless impersonation_read_only? && ViewingAs.config.read_only_layer?(:database)

      ActiveRecord::Base.while_preventing_writes { yield }
    rescue ActiveRecord::ReadOnlyError => e
      logger.error("[ViewingAs] blocked a write: #{e.message}") if respond_to?(:logger) && logger
      render plain: "Read-only while viewing another account.", status: :forbidden
    end

    # "No Cache-Control" is not "no caching": a CDN answers it with its default
    # TTL and would happily cache one person's account page for the next
    # visitor. Say it.
    def no_store_while_impersonating
      response.headers["Cache-Control"] = "no-store" if impersonating? && ViewingAs.config.no_store
    end

    def impersonation_payload
      raw = cookies.signed[ViewingAs.config.cookie_name]
      raw.blank? ? nil : JSON.parse(raw)
    rescue JSON::ParserError
      # A signed cookie that survived verification but is not the JSON we
      # wrote: ours, from an older shape. Treat as absent rather than 500ing.
      nil
    end

    def refuse_impersonation(admin, target, reason)
      record_viewing_event(admin, target, Kinds::REFUSED, detail: reason)
      Attempt.new(started: false, reason: reason)
    end

    def record_viewing_event(admin, user, kind, detail: nil)
      ViewingAs.config.event_class.record!(admin: admin, user: user, kind: kind,
                                           request: request, detail: detail)
    end

    def at(epoch)
      Time.zone ? Time.zone.at(epoch) : Time.at(epoch)
    end
  end
end
