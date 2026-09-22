require "rails/generators"
require "rails/generators/active_record"

module ViewingAs
  module Generators
    # rails generate viewing_as:install
    #
    # Writes the initializer, the events migration and an ImpersonationsController;
    # adds the two routes; includes the concern in ApplicationController after
    # Authentication; prepends the Current mixin; renders the banner in the
    # layout. Every step is idempotent and says what it skipped.
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :skip_migration, type: :boolean, default: false,
                   desc: "Skip the viewing_as_events migration (you keep your own log)"

      def create_initializer
        template "initializer.rb", "config/initializers/viewing_as.rb"
      end

      def create_migration_file
        return if options[:skip_migration]

        migration_template "migration.rb.tt", "db/migrate/create_viewing_as_events.rb"
      end

      def create_controller
        template "impersonations_controller.rb", "app/controllers/impersonations_controller.rb"
      end

      def add_routes
        route <<~ROUTES
          # Viewing an account as its owner. No id on the stop route: the cookie
          # already knows who, which is what lets the banner offer it from any page.
          post "impersonations/:id", to: "impersonations#create", as: :impersonation
          delete "impersonation", to: "impersonations#destroy", as: :stop_impersonation
        ROUTES
      end

      def include_controller_concern
        path = "app/controllers/application_controller.rb"
        line = "  include ViewingAs::Controller\n"
        return say_status(:skip, "#{path} already includes ViewingAs::Controller", :yellow) if contains?(path, "ViewingAs::Controller")

        if contains?(path, /^\s*include Authentication\s*$/)
          inject_into_file path, line, after: /^\s*include Authentication\s*\n/
        else
          inject_into_class path, "ApplicationController", line
        end
      end

      def prepend_current_mixin
        path = "app/models/current.rb"
        if File.exist?(destination(path))
          return say_status(:skip, "#{path} already prepends ViewingAs::CurrentUser", :yellow) if contains?(path, "ViewingAs::CurrentUser")

          inject_into_class path, "Current", "  prepend ViewingAs::CurrentUser\n"
        else
          template "current.rb", path
        end
      end

      def render_banner
        path = "app/views/layouts/application.html.erb"
        return say_status(:skip, "#{path} not found; render \"viewing_as/banner\" in your layout", :yellow) unless File.exist?(destination(path))
        return say_status(:skip, "#{path} already renders the banner", :yellow) if contains?(path, "viewing_as/banner")

        inject_into_file path, "    <%= render \"viewing_as/banner\" %>\n", after: /<body[^>]*>\n/
      end

      def show_next_steps
        say ""
        say "Next:"
        say "  1. Review config/initializers/viewing_as.rb: may_impersonate and may_be_viewed are the policy."
        say "  2. bin/rails db:migrate" unless options[:skip_migration]
        say "  3. Put a button somewhere: button_to \"View as\", impersonation_path(user), method: :post"
        say "  4. Style .viewing-as-banner, or copy the partial to app/views/viewing_as/_banner.html.erb."
      end

      private

      def users_table
        ViewingAs.config.user_klass.table_name
      rescue StandardError
        "users"
      end

      def destination(path)
        File.join(destination_root, path)
      end

      def contains?(path, needle)
        full = destination(path)
        File.exist?(full) && File.read(full).match?(needle.is_a?(Regexp) ? needle : Regexp.new(Regexp.escape(needle)))
      end
    end
  end
end
