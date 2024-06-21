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
        t = Time.now
        n = 0
        specs.each do |spec|
          adapter = @adapter
          _ = adapter # used in the instance_eval but generates a warning otherwise
          if spec.expected == Unit::FATAL
            @klass.instance_eval(<<~RUBY, spec.file, spec.line - 1)
              meth_name = "test_ #{spec.name}"
              define_method(meth_name.to_sym) do
                #{"Warning.stubs(:warn)" if spec.generates_ruby_warning}
                adapter.render(spec)
              rescue => e
                assert true
              else
                assert false, "Expected unrecoverable error, but none was raised"
              end
            RUBY
          else
            @klass.instance_eval(<<~RUBY, spec.file, spec.line - 1)
              meth_name = "test_ #{spec.name}"
              define_method(meth_name.to_sym) do
                #{"Warning.stubs(:warn)" if spec.generates_ruby_warning}
                actual = Timecop.freeze(TEST_TIME) do
                  adapter.render(spec)
                end
                assert spec.expected == actual, FailureMessage.new(spec, actual)
              end
            RUBY
          end
          n += 1
        end
        puts "Generated #{n} tests in #{Time.now - t}s"
      end
    end
  end
end
