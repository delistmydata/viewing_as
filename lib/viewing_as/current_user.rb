module ViewingAs
  # Prepend into the host's Current so that Current.user is the viewed account
  # while a session is on, and the signed-in user otherwise:
  #
  #   class Current < ActiveSupport::CurrentAttributes
  #     prepend ViewingAs::CurrentUser
  #     attribute :session
  #     delegate :user, to: :session, allow_nil: true
  #   end
  #
  # Prepend, not include, so it wins over a `delegate :user` or a hand-written
  # `user` already on the class; `super` then reaches whichever the host had.
  # With no such method it falls back to `session&.user`, the generator's shape.
  #
  # This is what lets every controller, model and job that reads Current.user
  # work unmodified while an admin is viewing an account. Anything that must
  # know who is really here reads Current.session.user, or the controller's
  # true_user.
  module CurrentUser
    def self.prepended(base)
      base.singleton_class.delegate :impersonated_user, :impersonation_expires_at,
                                    :impersonation_read_only, :impersonating?, to: :instance
    end

    def self.included(base)
      prepended(base)
    end

    def user
      ViewingAs::Current.impersonated_user || (defined?(super) ? super : session&.user)
    end

    def impersonated_user
      ViewingAs::Current.impersonated_user
    end

    def impersonation_expires_at
      ViewingAs::Current.expires_at
    end

    def impersonation_read_only
      ViewingAs::Current.read_only
    end

    def impersonating?
      ViewingAs::Current.impersonating?
    end
  end
end
