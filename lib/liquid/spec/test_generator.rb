require "timecop"
require_relative "failure_message"

module Liquid
  module Spec
    class TestGenerator
      TEST_TIME = Time.utc(2024, 01, 01, 0, 1, 58).freeze

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
            test_name =  "test_#{spec.name.gsub(/\s+/, "_")}".to_sym

            next if @klass.method_defined?(test_name)

            @klass.class_exec(@adapter) do |adapter|
              define_method(test_name) do
                Timecop.freeze(TEST_TIME) do
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
end
