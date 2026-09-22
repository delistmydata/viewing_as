module ViewingAs
  # The viewing state for the current request. Reset with every other
  # CurrentAttributes at the end of the request.
  #
  # Kept separate from the host's Current so the library never has to know
  # what that class is called or what else it holds. ViewingAs::CurrentUser is
  # the bridge that makes the host's Current.user answer with the viewed
  # account.
  class Current < ActiveSupport::CurrentAttributes
    attribute :impersonated_user, :expires_at, :read_only

    def impersonating?
      impersonated_user.present?
    end
  end
end
