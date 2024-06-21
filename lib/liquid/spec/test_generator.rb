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
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        n = 0
        _ = adapter = @adapter # used in the instance_eval but generates a warning otherwise
        specs.each do |spec|
          _ = meth_name = "test_ #{spec.name}" # again _ = needed for warning
          if spec.expected == Unit::FATAL
            @klass.instance_eval(<<~RUBY, spec.file, spec.line - 1)
              define_method(meth_name) do
                #{"Warning.stubs(:warn)" if spec.generates_ruby_warning}
                assert_raises(Object) { adapter.render(spec) }
              end
            RUBY
          else
            @klass.instance_eval(<<~RUBY, spec.file, spec.line - 1)
              define_method(meth_name) do
                #{"Warning.stubs(:warn)" if spec.generates_ruby_warning}
                actual = Timecop.freeze(TEST_TIME) { adapter.render(spec) }
                assert_equal(spec.expected, actual, FailureMessage.new(spec, actual))
              end
            RUBY
          end
          n += 1
        end
        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ms = ((t2 - t1) * 1000).round
        puts "\x1b[1;34m%% Generated #{n} tests in #{ms}ms\x1b[0m"
      end
    end
  end
end
