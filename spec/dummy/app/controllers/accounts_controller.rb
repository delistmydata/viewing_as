class AccountsController < ApplicationController
  def show
  end

  def update
    Current.user.update!(params.require(:user).permit(:name))
    redirect_to account_path, notice: "Saved."
  end

  # A GET that writes, on purpose: what the :database read-only layer is for.
  def touch
    Current.user.update_column(:name, "touched")
    redirect_to account_path
  end
end
