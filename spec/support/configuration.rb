# Change settings for one example and put them back, so the dummy app's
# initializer stays the baseline every other example runs against.
module ConfigurationHelpers
  def with_viewing_as(**overrides)
    config = ViewingAs.config
    saved = overrides.keys.to_h { |key| [ key, config.public_send(key) ] }
    overrides.each { |key, value| config.public_send("#{key}=", value) }
    yield
  ensure
    saved.each { |key, value| config.public_send("#{key}=", value) }
  end
end

RSpec.configure do |config|
  config.include ConfigurationHelpers
end
