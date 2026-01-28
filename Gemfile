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

# Use local liquid-c gem if available, otherwise use main from GitHub
local_liquid_c_path = File.expand_path("../liquid-c", __dir__)
if File.exist?(local_liquid_c_path)
  gem "liquid-c", path: local_liquid_c_path, require: false
else
  gem "liquid-c", github: "Shopify/liquid-c", branch: "main", require: false
end

# Core test dependencies
gem "minitest"
gem "minitest-focus"

# Development only
group :development do
  gem "rake"
  gem "activesupport", require: false
end

gem "base64", "~> 0.3.0"

gem "bigdecimal", "~> 4.0"
