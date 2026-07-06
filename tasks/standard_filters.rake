# frozen_string_literal: true

namespace :generate do
  desc "Generate spec tests from Shopify/liquid"
  task :standard_filters do
    require "yaml"
    require "liquid"
    require "minitest"
    require_relative "helpers"
    require_relative "../lib/liquid/spec/deps/liquid_ruby"
    Helpers.load_shopify_liquid
    Helpers.insert_patch(FILTER_PATCH_PATH, FILTER_PATCH)
    Helpers.insert_patch("./tmp/liquid/Gemfile", "gem \"activesupport\", \"~> 7.1\"\n")
    Helpers.reset_captures(FILTER_CAPTURE_PATH)
    run_standard_filters_tests
    Helpers.format_and_write_specs(FILTER_CAPTURE_PATH, FILTER_SPEC_FILE, metadata: { "hint" => FILTER_METADATA_HINT })
  end
end

FILTER_PATCH_PATH = "./tmp/liquid/test/integration/standard_filter_test.rb"
FILTER_PATCH = <<~RUBY
  require "active_support/core_ext/object/blank"
  require "active_support/core_ext/string/access"

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

  # Load YAML coders so YAML.dump produces instantiate: format
  require_relative(
    File.join(
      __dir__, "..", "..", "..", "..", "lib", "liquid", "spec", "deps", "yaml_coders",
    )
  )

  # Patch TestThing (defined above in this file) to serialize as ToSDrop
  TestThing.class_eval do
    def encode_with(coder)
      coder.represent_map(nil, { "instantiate:ToSDrop:" => { "foo" => @foo } })
    end
  end

  TEST_TIME = Time.utc(2024, 0o1, 0o1, 0, 1, 58).freeze
  require 'timecop'

  StandardFiltersTest::Filters.class_exec do
    @filter_methods.each do |method_name|
      define_method(method_name) do |*args|
        copy_of_args = StandardFilterPatch._deep_dup(args)
        result =  super(*args)
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
        "bundle exec rake base_test MT_SEED=12345 TEST=\"test/integration/standard_filter_test.rb\"" \
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

FILTER_METADATA_HINT = <<~HINT
  These generated filter specs cover Shopify/liquid filter behavior across many input
  types (strings, integers, floats, booleans, nil, arrays, hashes, drops, Dates). They
  are scored at complexity 160 — past the curated basics/ filter ramp — because failures
  are usually about cross-cutting behaviors, not the filter itself. When a single filter
  spec fails, first check the category it falls into:

  1. Date/Time rendering (render Date as YYYY-MM-DD before the filter applies)
  2. Float formatting (0.0 not 0; shortest round-trip, keep .0 on integer-valued floats)
  3. Type coercion (boolean->0/1, string->chars for first/last, strict contains equality)
  4. nil/empty handling (nil -> "" not "nil"; nil | size -> 0)
  5. Drops/Ruby objects (call to_liquid/to_s first; auto-tagged ruby_drops/ruby_types)

  See docs/filter_matrix_quirks.md for full details and worked examples.
HINT
