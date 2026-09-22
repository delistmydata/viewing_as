module UserHelpers
  PASSWORD = "correct-horse-battery-staple".freeze

  def create_user(email_address:, **attrs)
    User.create!(email_address: email_address, password: PASSWORD, **attrs)
  end

  def create_admin(email_address: "admin@example.com", **attrs)
    create_user(email_address: email_address, admin: true, **attrs)
  end

  # Through the real controller, so the signed cookie and the Session row
  # behave exactly as they do in production.
  def sign_in(user)
    post "/session", params: { email_address: user.email_address, password: PASSWORD }
  end

  def signed_in_session
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    Session.find_by(id: jar.signed[:session_id])
  end

  def impersonate(user)
    post "/impersonations/#{user.id}"
  end

  def events(kind, user:)
    ViewingAs::Event.where(kind: kind, user: user)
  end
end

RSpec.configure do |config|
  config.include UserHelpers, type: :request
  config.include UserHelpers, type: :model
end
