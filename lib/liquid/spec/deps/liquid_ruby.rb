# frozen_string_literal: true

# Pure drop implementations for testing - track state per-instance
# Each drop is self-contained and produces deterministic output

class TestThing < Liquid::Drop
  # A simple drop that renders a string based on its initial value
  # Tracks how many times properties are accessed via [] bracket notation
  # This is used in tests to verify filter behavior with custom drops.

  def initialize(foo = 0)
    @foo = foo
    @call_count = 0 # Track bracket accesses
  end

  def to_s
    "woot: #{@foo}"
  end

  attr_reader :foo

  def [](_whatever)
    @call_count += 1
    to_s
  end

  def to_liquid
    self
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
      @each_called = false
      @load_slice_called = false
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

# Stub implementations that track state in instance variables (no globals)
class StubTemplateFactory
  def initialize
    @call_count = 0
  end

  def count
    @call_count
  end

  def for(template_name)
    @call_count += 1
    template = Liquid::Template.new
    template.name = "some/path/" + template_name
    template
  end
end

class StubFileSystem
  def initialize(values)
    @values = values
    @call_count = 0
  end

  def file_read_count
    @call_count
  end

  def read_template_file(template_path)
    @call_count += 1
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
