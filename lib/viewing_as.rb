require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/current_attributes"

require "viewing_as/version"
require "viewing_as/configuration"
require "viewing_as/kinds"
require "viewing_as/current"
require "viewing_as/current_user"
require "viewing_as/controller"
require "viewing_as/cable"
require "viewing_as/engine" if defined?(Rails::Engine)

# Viewing an account as its owner, without being able to change it.
#
# The whole library is a controller concern (ViewingAs::Controller), a mixin for
# the host's Current (ViewingAs::CurrentUser), an event model (ViewingAs::Event)
# and a configuration object holding every decision that belongs to the host
# application. See README.md.
module ViewingAs
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    # For tests. Throws away every setting, including the host's.
    def reset_config!
      @config = Configuration.new
    end
  end
end
