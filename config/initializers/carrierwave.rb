require "carrierwave/storage/fog"

if Rails.env.test?
  CarrierWave.configure do |config|
    config.storage = :fog
    config.fog_credentials = {
      provider:              "AWS",
      aws_access_key_id:     "fake",
      aws_secret_access_key: "fake",
      region:                "us-west-2"
    }
    config.fog_directory  = "test-bucket"
    config.fog_public     = false
  end
else
  CarrierWave.configure do |config|
    config.fog_credentials = {
      provider:              "AWS",                        # required
      aws_access_key_id:     ENV["AWS_ACCESS_KEY_ID"],     # set in environment
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"], # set in environment
      region:                ENV["AWS_REGION"] || "us-west-2"
    }
    config.fog_directory  = ENV["AWS_BUCKET"]              # required
    config.fog_public     = false                          # optional, defaults to true
    config.fog_attributes = { cache_control: "public, max-age=3600" } # optional
  end
end
