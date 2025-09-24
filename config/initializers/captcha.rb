Recaptcha.configure do |config|
  # from https://www.google.com/recaptcha/admin
  config.site_key = ENV['CAPTCHA_SITE_KEY']
  config.secret_key = ENV['CAPTCHA_SECRET_KEY']
end
