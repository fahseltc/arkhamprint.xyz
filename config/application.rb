# config/application.rb

require_relative "boot"

require "rails"
# Only load the frameworks you need:
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
# Skip unused frameworks:
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
# require "active_storage/engine"
# require "action_cable/engine"
# require "sprockets/railtie"
# require "rails/test_unit/railtie"

# Require gems listed in Gemfile
Bundler.require(*Rails.groups)

module Arkhamprint
  class Application < Rails::Application
    config.load_defaults 8.0

    # Custom variables
    config.save_data_modes = [ :redis, :file ]
    config.save_data_mode = :file

    # Add your custom hosts
    config.hosts << "arkhamprint-xyz.onrender.com"
    config.hosts << "arkhamprint.xyz"

    # Autoload lib/ ignoring directories without Ruby files
    config.autoload_lib(ignore: %w[assets tasks])

    # Optional settings you can uncomment if needed
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
