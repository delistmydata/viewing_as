require "fileutils"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "viewing_as"

# The smallest app that looks like `rails new` + the authentication generator
# + `rails g viewing_as:install`. Everything under app/ is either the
# generator's output or the library's templates, copied verbatim so the
# specs exercise what a host would actually get.
module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "dummy-secret-key-base-long-enough-for-the-cookie-jar-0123456789"
    config.hosts.clear
    # log/ and tmp/ are gitignored, so a fresh checkout has neither.
    %w[ log tmp ].each { |dir| FileUtils.mkdir_p(File.expand_path("../#{dir}", __dir__)) }
    config.logger = ActiveSupport::Logger.new(File.expand_path("../log/test.log", __dir__))
    config.active_support.deprecation = :stderr
    config.action_dispatch.show_exceptions = :rescuable
    # Off in the suite, the way rails new's test environment leaves it; one
    # spec turns it back on around the action it is about.
    config.action_controller.allow_forgery_protection = false
    config.active_record.dump_schema_after_migration = false
  end
end
