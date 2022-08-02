require_relative "failure_message"

module Liquid
  module Spec
    class TestGenerator
      class << self
        def generate(klass, sources, adapter)
          new(klass, sources, adapter).generate
        end
      end
      def initialize(klass, sources, adapter)
        @klass = klass
        @sources = sources
        @adapter = adapter
      end

      def generate
        @sources.each do |source|
          source.each do |spec|
            @klass.class_exec(@adapter) do |adapter|
              define_method("test_#{spec.name}") do
                actual = adapter.render(spec)
                assert spec.expected == actual, FailureMessage.new(spec, actual)
              end
            end
          end
        end
      end
    end
  end
end
