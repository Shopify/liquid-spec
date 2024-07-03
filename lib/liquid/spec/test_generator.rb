require "timecop"
require_relative "failure_message"

module Liquid
  module Spec
    class TestGenerator
      TEST_TIME = Time.utc(2024, 01, 01, 0, 1, 58).freeze

      class << self
        def generate(klass, sources, adapter, run_command: nil)
          new(klass, sources, adapter, run_command:).generate
        end
      end
      def initialize(klass, sources, adapter, run_command: nil)
        @klass = klass
        @sources = sources
        @adapter = adapter
        @run_command = run_command
      end

      def generate
        @sources.each do |source|
          source.each do |spec|
            test_class_name, test_name = spec.name.split("#")

            if test_name.nil?
              test_name = test_class_name
              test_class_name = "MiscTest"
            end

            test_class = if @klass.const_defined?(test_class_name)
              @klass.const_get(test_class_name)
            else
              test_klass = Class.new(@klass)
              @klass.const_set(test_class_name, test_klass)
              test_klass
            end

            next if test_class.method_defined?(test_name)

            test_class.class_exec(@adapter) do |adapter|
              define_method(test_name) do
                exception = nil
                context = nil
                rendered = nil

                Timecop.freeze(TEST_TIME) do
                  begin
                    rendered, context = adapter.render(spec)
                  rescue => e
                    exception = e
                  end
                end

                message = FailureMessage.new(spec, rendered, exception:, run_command: @run_command, test_name:, context:)

                assert spec.expected == rendered, message
              rescue Minitest::Assertion => e
                e.set_backtrace([]) if exception
                raise
              end
            end
          end
        end
      end
    end
  end
end
