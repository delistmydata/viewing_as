module ForgeryProtectionHelpers
  # Wrap the action under test, never the sign-in.
  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end

RSpec.configure do |config|
  config.include ForgeryProtectionHelpers, type: :request
end
