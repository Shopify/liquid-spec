# frozen_string_literal: true

require 'yaml'
require 'liquid'
require 'minitest'
require 'pry-byebug'

require_relative(File.join(__dir__, "helpers"))

require_relative(
  File.join(
    __dir__, # liquid-spec/tasks
    "..",    # liquid-spec/
    "lib",
    "liquid",
    "spec",
    "deps",
    "liquid_ruby",
  )
)

namespace :generate do
  desc 'Generate spec tests from Shopify/liquid'
  task :liquid_ruby do
    Helpers.load_shopify_liquid
    Helpers.insert_patch(PATCH_PATH, PATCH)
    Helpers.reset_captures(CAPTURE_PATH)
    run_liquid_tests
    Helpers.format_and_write_specs(CAPTURE_PATH, SPEC_FILE)
  end
end


PATCH = <<~RUBY
require_relative(
  File.join(
    __dir__, # liquid-spec/tmp/liquid/test
    "..",    # liquid-spec/tmp/liquid
    "..",    # liquid-spec/tmp/
    "..",    # liquid-spec/
    "lib",
    "liquid",
    "spec",
    "deps",
    "shopify_liquid_patch",
  )
)
RUBY
PATCH_PATH = "./tmp/liquid/test/test_helper.rb"

CAPTURE_PATH = "./tmp/liquid-ruby-capture.yml"

def run_liquid_tests
  Bundler.with_unbundled_env do
    system("cd tmp/liquid && bundle install && bundle exec rake base_test && cd ../..")
  end
end

SPEC_FILE = File.join(
  __dir__, # liquid-spec/tasks
  "..",    # liquid-spec/
  "specs",
  "liquid_ruby",
  "specs.yml",
)
