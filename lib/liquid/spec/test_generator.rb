require "timecop"
require_relative "failure_message"

module Liquid
  module Spec
    class TestGenerator
      TEST_TIME = Time.utc(2022, 1, 1, 0, 1, 58).freeze

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
        each_spec do |s|
          @klass.class_exec(@adapter) do |adapter|
            define_method("test_#{s.name}") do
              Timecop.freeze(TEST_TIME) do
                actual = adapter.render(s)
                assert s.expected == actual, FailureMessage.new(s, actual)
              end
            end
          end
        end
      end

      private

      def each_spec(&block)
        # An adapter may define #permute_spec(s: Spec) -> [Spec].
        # If defined, this is expected to generate an array of specs derived from this one.
        do_permute = @adapter.respond_to?(:permute_spec)
        @sources.each do |source|
          source.each do |spec|
            if do_permute
              @adapter.permute_spec(spec).each(&block)
            else
              block.call(spec)
            end
          end
        end
      end
    end
  end
end
