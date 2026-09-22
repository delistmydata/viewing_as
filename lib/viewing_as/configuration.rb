module ViewingAs
  # Every decision that belongs to the host application, made explicit.
  #
  # The defaults are the Rails 8 authentication generator's shapes: a Current
  # with a `session` whose `user` is who is signed in, a `User` model, and an
  # `admin?` predicate on it. A host built some other way overrides the lambdas
  # and nothing else in the library needs to know.
  class Configuration
    # How long a viewing session lasts from the moment it starts. Absolute, not
    # sliding: enforced server-side off the timestamp in the cookie, and a
    # session that runs out is logged as expired.
    attr_accessor :timeout

    # Name of the signed cookie that carries the viewing state. It is NOT the
    # Rails session, and that is deliberate: reading a second signed cookie
    # costs nothing on a page that never loads the session, whereas merely
    # loading `session[]` makes Rack emit Set-Cookie and un-caches the page at
    # any CDN in front of the app.
    attr_accessor :cookie_name

    # ->(controller) { who is actually here }. Every permission check and every
    # log row uses this, never the impersonated user.
    attr_accessor :true_user

    # ->(controller) { an id that changes when the true user signs out }. The
    # cookie is bound to it, so a cookie minted under one sign-in is inert
    # under the next.
    attr_accessor :session_id

    # ->(controller) { load the sign-in state }. Called before the true user is
    # consulted on every request that carries the cookie, so that surfaces
    # which skip authentication still see the banner.
    attr_accessor :resume_session

    # ->(id) { the account named in the cookie, or nil }.
    attr_accessor :find_target

    # ->(user) { true if this person may view accounts at all }.
    attr_accessor :may_impersonate

    # ->(target, admin) { true, or a String saying why not }. Consulted when a
    # session starts (the reason is logged as a refusal) and again on every
    # request while it lasts (a false answer ends it, logged as revoked). This
    # is where consent lives: return a reason when the account owner has said no.
    attr_accessor :may_be_viewed

    # ->(user) { how to name this person in the banner and the log }.
    attr_accessor :display

    # The class (or its name) that records events. Must respond to
    # record!(admin:, user:, kind:, request:, detail:). The default is the
    # library's own table; point it at your own model to keep one log.
    attr_accessor :event_model

    # Name of the host's user class, for the default event model's associations.
    attr_accessor :user_class

    # For the default event model: page-view rows within this window collapse
    # into one. Lifecycle rows (start, stop, expired, revoked, refused) never do.
    attr_accessor :dedupe_window

    # Whether a viewing session is read-only unless the controller says
    # otherwise when it starts one. See #read_only_layers.
    attr_accessor :read_only

    # Which guards enforce read-only. :policy refuses every request that is not
    # GET or HEAD. :database wraps the action in
    # ActiveRecord::Base.while_preventing_writes for whatever the policy cannot
    # see. Both by default; drop :database only if an impersonated GET has to
    # write something and you accept what that means.
    attr_accessor :read_only_layers

    # Stamp Cache-Control: no-store on every response rendered while viewing,
    # so no cache between the browser and the app can hand one person's page
    # to the next.
    attr_accessor :no_store

    # -> { whether the cookie is marked Secure }.
    attr_accessor :secure_cookie

    def initialize
      @timeout = 30.minutes
      @cookie_name = :impersonation
      @true_user = ->(_controller) { ::Current.session&.user }
      @session_id = ->(_controller) { ::Current.session&.id }
      @resume_session = lambda do |controller|
        controller.send(:resume_session) if controller.respond_to?(:resume_session, true)
      end
      @find_target = ->(id) { ViewingAs.config.user_klass.find_by(id: id) }
      @may_impersonate = ->(user) { user.respond_to?(:admin?) && user.admin? }
      @may_be_viewed = lambda do |target, _admin|
        if target.respond_to?(:admin?) && target.admin?
          "That account is an administrator."
        else
          true
        end
      end
      @display = ->(user) { user.try(:email_address) || user.try(:email) || user.to_s }
      @event_model = "ViewingAs::Event"
      @user_class = "User"
      @dedupe_window = 15.minutes
      @read_only = true
      @read_only_layers = %i[ policy database ]
      @no_store = true
      @secure_cookie = -> { defined?(::Rails) && ::Rails.env.production? }
    end

    def event_class
      event_model.is_a?(String) ? event_model.constantize : event_model
    end

    def user_klass
      user_class.is_a?(String) ? user_class.constantize : user_class
    end

    def read_only_layer?(layer)
      Array(read_only_layers).map(&:to_sym).include?(layer)
    end

    # may_be_viewed may take (target) or (target, admin). Returns nil when the
    # account may be viewed, otherwise the reason it may not.
    def refusal_for(target, admin)
      answer = may_be_viewed.arity.abs >= 2 ? may_be_viewed.call(target, admin) : may_be_viewed.call(target)
      case answer
      when true, nil then nil
      when String then answer
      else "That account cannot be viewed."
      end
    end
  end
end
