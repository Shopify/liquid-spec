source "https://rubygems.org"

gemspec

group :development, :test do
  gem 'liquid', git: "https://github.com/Shopify/liquid", ref: "3ff4170cb0571648a4a46d45ad8de3875cfed75b"
  gem 'rake'
end

group :test do
  gem 'base64' # bootsnap dep, should add upstream
  gem 'bigdecimal' # bootsnap dep, should add upstream
  gem 'bootsnap'
  gem 'minitest'
  gem 'minitest-focus', require: false
  gem 'mocha'
  gem 'pry-byebug'
end
