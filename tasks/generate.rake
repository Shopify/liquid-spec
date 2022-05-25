# frozen_string_literal: true

require 'yaml'
require 'liquid'
require 'minitest'
require 'pry-byebug'
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
  task :liquid do
    load_shopify_liquid
    insert_patch
    reset_captures
    run_liquid_tests
    format_and_write_specs
  end
end

def load_shopify_liquid
  if File.exist?("./tmp/liquid")
    `git -C tmp/liquid pull --depth 1 https://github.com/Shopify/liquid.git`
  else
    `git clone --depth 1 https://github.com/Shopify/liquid.git ./tmp/liquid`
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
FILE_PATH = "./tmp/liquid/test/test_helper.rb"
def insert_patch
  return if File.read(FILE_PATH).match("liquid_spec/tmp/liquid/test")
  File.write(
    FILE_PATH,
    PATCH,
    mode: "a+"
  )
end

CAPTURE_PATH = "./tmp/liquid-ruby-capture.yml"
def reset_captures
  if File.exist?(CAPTURE_PATH)
    File.delete(CAPTURE_PATH)
    File.write(CAPTURE_PATH, "---\n", mode: "a+")
  end
end

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
def format_and_write_specs
  yaml = File.read(CAPTURE_PATH)
  data = YAML.unsafe_load(yaml)
  data.sort_by! { |h| h["name"] }
  data.uniq!
  File.write(SPEC_FILE, YAML.dump(data))
end
