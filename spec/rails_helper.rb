ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "rspec/rails"

ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include ActiveSupport::Testing::TimeHelpers
  config.example_status_persistence_file_path = File.expand_path("examples.txt", __dir__)
  config.disable_monkey_patching!
end
