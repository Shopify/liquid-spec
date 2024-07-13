# frozen_string_literal: true

require "yaml"
require "liquid"
require "minitest"
require "pry-byebug"

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
  ),
)

namespace :generate do
  desc "Generate spec tests from Shopify/liquid"
  task :standard_filters do
    Helpers.load_shopify_liquid
    Helpers.insert_patch(FILTER_PATCH_PATH, FILTER_PATCH)
    Helpers.reset_captures(FILTER_CAPTURE_PATH)
    run_standard_filters_tests
    Helpers.format_and_write_specs(FILTER_CAPTURE_PATH, FILTER_SPEC_FILE)
  end
end

FILTER_PATCH_PATH = "./tmp/liquid/test/integration/standard_filter_test.rb"
FILTER_PATCH = <<~RUBY
  require_relative(
    File.join(
      __dir__, # liquid-spec/tmp/liquid/test/integration
      "..",    # liquid-spec/tmp/liquid/test
      "..",    # liquid-spec/tmp/liquid
      "..",    # liquid-spec/tmp/
      "..",    # liquid-spec/
      "lib",
      "liquid",
      "spec",
      "deps",
      "standard_filter_patch",
    )
  )

  StandardFiltersTest::Filters.class_exec do
    @filter_methods.each do |method_name|
      define_method(method_name) do |*args|
        copy_of_args = StandardFilterPatch._deep_dup(args)
        result = super(*args)
        StandardFilterPatch.generate_spec(method_name, result, *copy_of_args)
        result
      rescue => e
        raise e if e.is_a?(Liquid::Error)
        raise Liquid::ArgumentError, e.message, e.backtrace
      end
    end
  end
RUBY

FILTER_CAPTURE_PATH = "./tmp/standard-filters-capture.yml"

def run_standard_filters_tests
  Bundler.with_unbundled_env do
    system(
      "cd tmp/liquid &&" \
        "bundle install && " \
        "bundle exec rake base_test TEST=\"test/integration/standard_filter_test.rb\"" \
        "&& cd ../..",
    )
  end
end

FILTER_SPEC_FILE = File.join(
  __dir__, # liquid-spec/tasks
  "..",    # liquid-spec/
  "specs",
  "liquid_ruby",
  "standard_filters.yml",
)
