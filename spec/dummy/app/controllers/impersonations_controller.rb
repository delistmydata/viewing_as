# Starting and stopping a viewing session. The read-only guards are inherited
# from ApplicationController; #destroy is the one write they must let through,
# because it is the way out.
class ImpersonationsController < ApplicationController
  # NOT require_authentication, deliberately. That redirects to sign-in, and a
  # redirect is an answer: it tells whoever is poking at the URL that it
  # exists and wants a session. A signed-out stranger, a signed-in customer
  # and a made-up id all get the same 404 below.
  allow_unauthenticated_access
  before_action :require_impersonator
  skip_before_action :refuse_writes_while_impersonating, only: :destroy
  skip_around_action :read_only_while_impersonating, only: :destroy

  def create
    target = User.find(params[:id])
    attempt = impersonate(target)

    if attempt.started?
      redirect_to root_path, notice: "Viewing as #{ViewingAs.config.display.call(target)}."
    else
      redirect_back_or_to root_path, alert: attempt.reason
    end
  end

  def destroy
    end_impersonation!
    redirect_to root_path, notice: "Stopped viewing that account.", status: :see_other
  end

  private

  def require_impersonator
    ViewingAs.config.resume_session.call(self)
    return if true_user && ViewingAs.config.may_impersonate.call(true_user)

    raise ActiveRecord::RecordNotFound
  end
end
