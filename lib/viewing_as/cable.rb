module ViewingAs
  # For ApplicationCable::Connection.
  #
  # A connection identifies itself by the SESSION's user and has no request,
  # no filter chain and nothing the read-only guard can wrap. A channel opened
  # while an admin is viewing an account would therefore run as the admin,
  # with the admin's reach, from a page rendered as somebody else. The honest
  # answer is to refuse the connection until the viewing session ends:
  #
  #   class Connection < ActionCable::Connection::Base
  #     include ViewingAs::Cable
  #     identified_by :current_user
  #
  #     def connect
  #       reject_unauthorized_connection if viewing_another_account?
  #       ...
  module Cable
    private

    def viewing_another_account?
      cookies.signed[ViewingAs.config.cookie_name].present?
    end
  end
end
