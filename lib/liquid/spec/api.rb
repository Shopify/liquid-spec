# frozen_string_literal: true

require_relative "spec_loader"
require_relative "adapter_runner"

module Liquid
  module Spec
    # Simple top-level API for liquid-spec
    #
    # Example usage:
    #   specs = Liquid::Spec.load_specs(suite: :basics, filter: "assign")
    #   adapter = Liquid::Spec.load_adapter("examples/liquid_ruby.rb")
    #   result = adapter.run(specs) { |r| print r.passed? ? "." : "F" }
    #   puts result.summary
    #
    module API
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

        # Run specs against an adapter
        # @param adapter [AdapterRunner] loaded adapter
        # @param specs [Array<LazySpec>] specs to run
        # @yield [SpecResult] each result as it completes
        # @return [RunResult]
        def run(adapter, specs, &block)
          adapter.run(specs, &block)
        end
      end
    end

    # Convenience methods at module level
    extend API
  end
end
