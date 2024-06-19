require "timecop"
require_relative "failure_message"

module Liquid
  module Spec
    class TestGenerator
      TEST_TIME = Time.utc(2008, 5, 8, 15, 28, 13).freeze

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

      def specs
        return to_enum(:specs) unless block_given?
        @sources.each do |source|
          source.each { |spec| yield spec }
        end
      end

      def generate
        specs.each do |spec|
          adapter = @adapter
          @klass.instance_eval(<<~RUBY, spec.file, spec.line)
            define_method(:"test_ #{spec.name}") do
              actual = Timecop.freeze(TEST_TIME) do
                adapter.render(spec)
              end
              assert spec.expected == actual, FailureMessage.new(spec, actual)
            end
          RUBY
          # @klass.class_exec(@adapter) do |adapter|
          #   define_method("test_#{spec.name}") do
          #     Timecop.freeze(TEST_TIME) do
          #       actual = adapter.render(spec)
          #       assert spec.expected == actual, FailureMessage.new(spec, actual)
          #     end
          #   end
          # end
        end
      end
    end
  end
end
