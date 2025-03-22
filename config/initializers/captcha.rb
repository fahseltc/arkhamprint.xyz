Recaptcha.configure do |config|
  # from https://www.google.com/recaptcha/admin
  config.site_key = Rails.application.credentials.dig(:captcha, :site_key)
  config.secret_key = Rails.application.credentials.dig(:captcha, :secret_key)
end
