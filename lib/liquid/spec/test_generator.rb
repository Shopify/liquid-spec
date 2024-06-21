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
          _ = m = "test_ #{spec.name}" # again _ = needed for warning
          _ = w = spec.generates_ruby_warning ? "Warning.stubs(:warn); " : ""

          # source is kept to one line so that our line tracking lie remains accurate
          source = if spec.expected == Unit::FATAL
            "define_method(m) { #{w} assert_raises(Object) { adapter.render(spec) } }"
          else
            "define_method(m) { #{w} assert_equal(spec.expected, Timecop.freeze(TEST_TIME) { adapter.render(spec) })}"
          end
          @klass.instance_eval(source, spec.file, spec.line + 1)
          n += 1
        end
        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ms = ((t2 - t1) * 1000).round
        puts "\x1b[1;34m%% Generated #{n} tests in #{ms}ms\x1b[0m"
      end
    end
  end
end
