# Dummy-only. Shows the per-session override; a host decides who may ask for it.
class WritableImpersonationsController < ImpersonationsController
  def create
    target = User.find(params[:id])
    attempt = impersonate(target, read_only: false)

    if attempt.started?
      redirect_to root_path, notice: "Viewing as #{target.email_address}, writable."
    else
      redirect_back_or_to root_path, alert: attempt.reason
    end
  end
end
