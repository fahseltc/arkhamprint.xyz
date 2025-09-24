require 'carrierwave/storage/fog'

CarrierWave.configure do |config|
  config.fog_provider = 'fog/aws'                        # required
  config.fog_credentials = {
    provider:              'AWS',                        # required
    aws_access_key_id:     ENV['AWS_ACCESS_KEY_ID'],     # set in environment
    aws_secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'], # set in environment
    region:                ENV['AWS_REGION'] || 'us-west-2'
  }
  config.fog_directory  = ENV['AWS_BUCKET']              # required
  config.fog_public     = false                          # optional, defaults to true
  config.fog_attributes = { cache_control: "public, max-age=3600" } # optional
end
