# frozen_string_literal: true

# Global state for test drops - reset between spec runs to ensure isolation
module LiquidSpec
  module Globals
    @states = {}

    class << self
      def current
        key = current_key
        @states[key] ||= State.new
      end

      def reset!
        key = current_key
        @states[key] = State.new
      end

      private

      def current_key
        # Use box object_id if in a box, otherwise :main
        if defined?(Ruby::Box) && Ruby::Box.current
          Ruby::Box.current.object_id
        else
          :main
        end
      end
    end

    class State
      def initialize
        @counters = Hash.new(0)
        @context_histories = Hash.new { |h, k| h[k] = [] }
      end

      # Get and increment a counter (for TestThing etc)
      def increment(key)
        @counters[key] += 1
      end

      # Get current counter value without incrementing
      def counter(key)
        @counters[key]
      end

      # Get context history for a drop (keyed by object_id)
      def context_history(drop_id)
        @context_histories[drop_id]
      end
    end
  end
end

class TestThing
  def initialize(foo: 0)
    @initial_foo = foo
  end

  def to_s
    "woot: #{current_foo}"
  end

  def foo
    # offset the to_liquid call since these tests are not usually called from a liquid template
    current_foo - 1
  end

  def [](_whatever)
    to_s
  end

  def to_liquid
    LiquidSpec::Globals.current.increment(:test_thing)
    self
  end

  private

  def current_foo
    @initial_foo + LiquidSpec::Globals.current.counter(:test_thing)
  end
end

class TestDrop < Liquid::Drop
  def initialize(value:)
    @value = value
  end

  attr_reader :value

  def registers
    { @value => @context.registers[@value] }
  end
end

class TestEnumerable < Liquid::Drop
  include Enumerable

  def each(&block)
    [{ "foo" => 1, "bar" => 2 }, { "foo" => 2, "bar" => 1 }, { "foo" => 3, "bar" => 3 }].each(&block)
  end
end

class NumberLikeThing < Liquid::Drop
  def initialize(amount)
    @amount = amount
  end

  def to_number
    @amount
  end
end

class ThingWithToLiquid
  def to_liquid
    "foobar"
  end
end

class ForTagTest
  class LoaderDrop < Liquid::Drop
    attr_accessor :each_called, :load_slice_called

    def initialize(data)
      @data = data
    end

    def each(&block)
      @each_called = true
      @data.each(&block)
    end

    def load_slice(from, to)
      @load_slice_called = true
      @data[(from..to - 1)]
    end
  end
end

class TableRowTest
  class ArrayDrop < Liquid::Drop
    include Enumerable

    def initialize(array)
      @array = array
    end

    def each(&block)
      @array.each(&block)
    end
  end
end

class IntegerDrop < Liquid::Drop
  def initialize(value)
    super()
    @value = value.to_i
  end

  def ==(other)
    @value == other
  end

  def to_s
    @value.to_s
  end

  def to_liquid_value
    @value
  end
end

class ThingWithValue < Liquid::Drop
  def value
    3
  end
end

class BooleanDrop < Liquid::Drop
  def initialize(value)
    super()
    @value = value
  end

  def ==(other)
    @value == other
  end

  def to_liquid_value
    @value
  end

  def to_s
    @value ? "Yay" : "Nay"
  end
end

class CustomToLiquidDrop < Liquid::Drop
  def initialize(value)
    @value = value
  end

  def to_liquid
    @value
  end
end

class HashWithCustomToS < Hash
  def to_s
    "kewl"
  end
end

class HashWithoutCustomToS < Hash
end

class StringDrop < Liquid::Drop
  include Comparable

  def initialize(value)
    super()
    @value = value
  end

  def to_liquid_value
    @value
  end

  def to_s
    @value
  end

  def to_str
    @value
  end

  def inspect
    "#<StringDrop @value=#{@value.inspect}>"
  end

  def <=>(other)
    to_liquid_value <=> Liquid::Utils.to_liquid_value(other)
  end
end

class ErrorDrop < Liquid::Drop
  def standard_error
    raise Liquid::StandardError, "standard error"
  end

  def argument_error
    raise Liquid::ArgumentError, "argument error"
  end

  def syntax_error
    raise Liquid::SyntaxError, "syntax error"
  end

  def runtime_error
    raise "runtime error"
  end

  def exception
    raise Exception, "exception"
  end
end

class SettingsDrop < Liquid::Drop
  def initialize(settings)
    super()
    @settings = settings
  end

  def liquid_method_missing(key)
    @settings[key]
  end
end

class StubTemplateFactory
  def initialize
    @initial_count = LiquidSpec::Globals.current.counter(:template_factory)
  end

  def count
    LiquidSpec::Globals.current.counter(:template_factory) - @initial_count
  end

  def for(template_name)
    LiquidSpec::Globals.current.increment(:template_factory)
    template = Liquid::Template.new
    template.name = "some/path/" + template_name
    template
  end
end

class StubFileSystem
  def initialize(values)
    @values = values
    @initial_count = LiquidSpec::Globals.current.counter(:file_read)
  end

  def file_read_count
    LiquidSpec::Globals.current.counter(:file_read) - @initial_count
  end

  def read_template_file(template_path)
    LiquidSpec::Globals.current.increment(:file_read)
    @values.fetch(template_path) do
      raise Liquid::FileSystemError, "Could not find asset #{template_path}"
    end
  end

  def to_h
    @values.transform_keys(&:to_s)
  end
end

class StubExceptionRenderer
  attr_reader :rendered_exceptions

  def initialize(raise_internal_errors: true)
    @raise_internal_errors = raise_internal_errors
    @rendered_exceptions = []
  end

  def call(exception)
    @rendered_exceptions << exception

    if @raise_internal_errors && exception.is_a?(Liquid::InternalError)
      raise exception
    end

    exception
  end
end
