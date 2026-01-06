# frozen_string_literal: true

# liquid-spec: Test suite for Liquid template implementations
#
# Main API:
#   specs = Liquid::Spec.load_specs(suite: :basics, filter: "assign")
#   adapter = Liquid::Spec.load_adapter("examples/liquid_ruby.rb")
#   result = adapter.run(specs) { |r| print r.passed? ? "." : "F" }
#   puts result.summary

require_relative "spec/version"
require_relative "spec/suite"
require_relative "spec/lazy_spec"
require_relative "spec/spec_loader"
require_relative "spec/adapter_runner"
require_relative "spec/api"

module Liquid
  module Spec
    # Spec directory constant (defined in suite.rb, but provide fallback)
    SPEC_DIR = File.expand_path("../../specs", __dir__) unless defined?(SPEC_DIR)

    class << self
      # Load specs from suites
      # @param suite [Symbol] :all, :basics, :liquid_ruby, etc.
      # @param filter [String, Regexp] filter specs by name
      # @return [Array<LazySpec>]
      def load_specs(suite: :all, filter: nil)
        SpecLoader.load_all(suite: suite, filter: filter)
      end

      # Create an adapter runner and load a DSL file
      # @param path [String] path to adapter file (with or without .rb)
      # @return [AdapterRunner]
      def load_adapter(path)
        runner = AdapterRunner.new
        runner.load_dsl(path)
        runner
      end
    end
  end
end
