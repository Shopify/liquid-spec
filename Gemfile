# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Use local liquid gem if available, otherwise use latest from rubygems
local_liquid_path = File.expand_path("../liquid", __dir__)
if File.exist?(local_liquid_path)
  gem "liquid", path: local_liquid_path
else
  gem "liquid"
end

# Core test dependencies
gem "minitest"
gem "minitest-focus"
gem "timecop"

# Development only
group :development do
  gem "rake"
end

gem "base64", "~> 0.3.0"
