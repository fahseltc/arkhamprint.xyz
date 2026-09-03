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

    # PDF storage backend. Uses S3 when AWS credentials are configured,
    # otherwise falls back to the local filesystem so the app runs end-to-end
    # in development without any AWS setup (see PdfStorage).
    #
    # FORCE_USE_LOCAL=true forces local storage even when AWS is configured —
    # useful for testing the local path locally without unsetting AWS vars.
    force_local = ActiveModel::Type::Boolean.new.cast(ENV["FORCE_USE_LOCAL"])
    config.pdf_storage_mode = (ENV["AWS_BUCKET"].present? && !force_local) ? :s3 : :local

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
