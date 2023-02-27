source "https://rubygems.org"

gemspec

group :development, :test do
  # DO NOT MERGE THIS
  gem 'liquid', git: "https://github.com/Shopify/liquid", branch: "error-message-with-filepath"
  gem 'rake'
end

group :test do
  gem 'minitest'
  gem 'minitest-focus', require: false
  gem 'mocha'
  gem 'pry-byebug'
end
