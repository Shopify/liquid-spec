# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Use local liquid gem if available, otherwise use main from GitHub
local_liquid_path = File.expand_path("../liquid", __dir__)
if File.exist?(local_liquid_path)
  gem "liquid", path: local_liquid_path
else
  gem "liquid", github: "Shopify/liquid", branch: "main"
end

# Core test dependencies
gem "minitest"
gem "minitest-focus"

# Development only
group :development do
  gem "rake"
  gem "activesupport", require: false
  gem "liquid-c", require: false
end

gem "base64", "~> 0.3.0"
