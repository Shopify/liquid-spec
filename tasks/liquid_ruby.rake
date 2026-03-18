# frozen_string_literal: true

namespace :generate do
  desc "Generate spec tests from Shopify/liquid"
  task :liquid_ruby do
    require "yaml"
    require "liquid"
    require "minitest"
    require_relative "helpers"
    require_relative "../lib/liquid/spec/deps/liquid_ruby"
    Helpers.load_shopify_liquid
    Helpers.insert_patch(PATCH_PATH, PATCH)
    Helpers.insert_patch(PATCH_PATH, <<~RUBY)
      require "active_support/core_ext/object/blank"
      require "active_support/core_ext/string/access"
    RUBY

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

  # Load YAML coders so YAML.dump produces instantiate: format
  require_relative(
    File.join(
      __dir__, "..", "..", "..", "lib", "liquid", "spec", "deps", "yaml_coders",
    )
  )

  # Patch test classes to serialize as instantiate: format.
  # Uses Minitest's before_setup hook to lazily add encode_with
  # after test files define their classes.
  module YAMLCoderPatcher
    @@patched = false

    def before_setup
      super
      return if @@patched
      @@patched = true

      # Namespaced classes from specific test files
      patch_class(ForTagTest::LoaderDrop, "LoaderDrop") { |o| { "data" => o.instance_variable_get(:@data) } } if defined?(ForTagTest::LoaderDrop)
      patch_class(TableRowTest::ArrayDrop, "ArrayDrop") { |o| { "array" => o.instance_variable_get(:@array) } } if defined?(TableRowTest::ArrayDrop)

      # Classes from test_helper.rb
      patch_class(::TestThing, "ToSDrop") { |o| { "foo" => o.instance_variable_get(:@foo) } } if defined?(::TestThing)
      patch_class(::ThingWithToLiquid, "ThingWithToLiquid") { |_| {} } if defined?(::ThingWithToLiquid)
      patch_class(::StubTemplateFactory, "StubTemplateFactory") { |_| {} } if defined?(::StubTemplateFactory)

      if defined?(::HashWithCustomToS) && !::HashWithCustomToS.method_defined?(:encode_with)
        ::HashWithCustomToS.define_method(:encode_with) do |coder|
          coder.represent_map(nil, { "instantiate:HashWithCustomToS:" => Hash[self] })
        end
      end

      if defined?(::HashWithoutCustomToS) && !::HashWithoutCustomToS.method_defined?(:encode_with)
        ::HashWithoutCustomToS.define_method(:encode_with) do |coder|
          coder.represent_map(nil, { "instantiate:HashWithoutCustomToS:" => Hash[self] })
        end
      end
    end

    private

    def patch_class(klass, name, &params_block)
      return if klass.method_defined?(:encode_with)
      klass.define_method(:encode_with) do |coder|
        coder.represent_map(nil, { "instantiate:\#{name}:" => params_block.call(self) })
      end
    end
  end
  Minitest::Test.prepend(YAMLCoderPatcher)
RUBY
PATCH_PATH = "./tmp/liquid/test/test_helper.rb"

CAPTURE_PATH = "./tmp/liquid-ruby-capture.yml"

def run_liquid_tests
  Bundler.with_unbundled_env do
    system("cd tmp/liquid && bundle exec rake base_test MT_SEED=12345 && cd ../..")
  end
end

SPEC_FILE = File.join(
  __dir__, # liquid-spec/tasks
  "..",    # liquid-spec/
  "specs",
  "liquid_ruby",
  "specs.yml",
)
