# frozen_string_literal: true

require_relative "../spec_loader"

# Pure drop implementations for testing - track state per-instance
# Each drop is self-contained and produces deterministic output

class CountingDrop < Liquid::Drop
  # A drop that counts how many times [] is accessed.
  # to_s returns "N accesses" where N is the count.
  # Used to verify that filters like `map` actually call [] on drops.
  #
  # Example YAML:
  #   {"instantiate:CountingDrop" => {}}
  #   # After one [] call: to_s returns "1 accesses"

  def initialize(_params = {})
    @access_count = 0
  end

  def to_s
    "#{@access_count} accesses"
  end

  attr_reader :access_count

  def [](_property)
    @access_count += 1
    to_s
  end

  def to_liquid
    self
  end
end

class ToSDrop < Liquid::Drop
  # A drop with a configurable to_s value.
  # Used to test that filters correctly call to_s on drops.
  #
  # Example YAML:
  #   {"instantiate:ToSDrop" => {"to_s" => "hello"}}
  #   # to_s returns "hello"
  #
  # Also accepts "foo" param for legacy TestThing compatibility:
  #   {"instantiate:ToSDrop" => {"foo" => 3}}
  #   # to_s returns "woot: 3"

  def initialize(params = {})
    params = { "to_s" => params } unless params.is_a?(Hash)

    @to_s_value = if params.key?("to_s") || params.key?(:to_s)
      params["to_s"] || params[:to_s] || ""
    elsif params.key?("foo") || params.key?(:foo)
      # Legacy TestThing format
      "woot: #{params["foo"] || params[:foo]}"
    else
      ""
    end
  end

  def to_s
    @to_s_value.to_s
  end

  def to_liquid
    self
  end
end

class TestDrop < Liquid::Drop
  def initialize(params = {})
    params = { "value" => params } unless params.is_a?(Hash)
    @value = params["value"] || params[:value]
  end

  attr_reader :value

  def registers
    { @value => @context.registers[@value] }
  end
end

class TestEnumerable < Liquid::Drop
  include Enumerable

  def initialize(_params = {})
    # No params needed
  end

  def each(&block)
    [{ "foo" => 1, "bar" => 2 }, { "foo" => 2, "bar" => 1 }, { "foo" => 3, "bar" => 3 }].each(&block)
  end
end

class NumberLikeThing < Liquid::Drop
  def initialize(params = {})
    params = { "amount" => params } unless params.is_a?(Hash)
    @amount = params["amount"] || params[:amount] || 0
  end

  def to_number
    @amount
  end
end

class ThingWithToLiquid
  def initialize(_params = {})
    # No params needed
  end

  def to_liquid
    "foobar"
  end
end

# LoaderDrop for ForTagTest - accepts hash params
class LoaderDrop < Liquid::Drop
  attr_accessor :each_called, :load_slice_called

  def initialize(params = {})
    params = { "data" => params } unless params.is_a?(Hash)
    @data = params["data"] || params[:data] || []
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

# ArrayDrop for TableRowTest - accepts hash params
class ArrayDrop < Liquid::Drop
  include Enumerable

  def initialize(params = {})
    params = { "array" => params } unless params.is_a?(Hash)
    @array = params["array"] || params[:array] || []
  end

  def each(&block)
    @array.each(&block)
  end
end

class IntegerDrop < Liquid::Drop
  def initialize(params = {})
    super()
    params = { "value" => params } unless params.is_a?(Hash)
    value = params["value"] || params[:value] || 0
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
  def initialize(_params = {})
    # No params needed
  end

  def value
    3
  end
end

class BooleanDrop < Liquid::Drop
  def initialize(params = {})
    super()
    params = { "value" => params } unless params.is_a?(Hash)
    @value = params["value"] || params[:value] || false
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
  def initialize(params = {})
    params = { "value" => params } unless params.is_a?(Hash)
    @value = params["value"] || params[:value]
  end

  def to_liquid
    @value
  end
end

# Wrapper to create Range objects from params
class RangeWrapper
  def self.new(params)
    if params.is_a?(Array)
      Range.new(params[0], params[1])
    elsif params.is_a?(Hash)
      Range.new(params["begin"] || params[:begin], params["end"] || params[:end])
    else
      params
    end
  end
end

class HashWithCustomToS < Hash
  def self.new(params = {})
    h = allocate
    h.merge!(params) if params.is_a?(Hash)
    h
  end

  def to_s
    "kewl"
  end
end

class HashWithoutCustomToS < Hash
  def self.new(params = {})
    h = allocate
    # Convert string keys to symbols for this hash
    if params.is_a?(Hash)
      params.each { |k, v| h[k.to_sym] = v.is_a?(String) ? v.to_sym : v }
    end
    h
  end
end

class StringDrop < Liquid::Drop
  include Comparable

  def initialize(params = {})
    super()
    params = { "value" => params } unless params.is_a?(Hash)
    @value = params["value"] || params[:value]
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
  def initialize(_params = {})
    # No params needed
  end

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
  def initialize(params = {})
    super()
    # Accept either {"settings" => {...}} or raw settings hash
    @settings = if params.is_a?(Hash) && (params.key?("settings") || params.key?(:settings))
      params["settings"] || params[:settings]
    else
      params
    end
  end

  def liquid_method_missing(key)
    @settings[key.to_s] || @settings[key.to_sym]
  end
end

# Stub implementations that track state in instance variables (no globals)
class StubTemplateFactory
  def initialize(_params = {})
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

# Register all test classes with the ClassRegistry
# Each lambda creates a fresh instance for every test
Liquid::Spec::ClassRegistry.register("CountingDrop") { |p| CountingDrop.new(p) }
Liquid::Spec::ClassRegistry.register("ToSDrop") { |p| ToSDrop.new(p) }
Liquid::Spec::ClassRegistry.register("TestDrop") { |p| TestDrop.new(p) }
Liquid::Spec::ClassRegistry.register("TestEnumerable") { |p| TestEnumerable.new(p) }
Liquid::Spec::ClassRegistry.register("NumberLikeThing") { |p| NumberLikeThing.new(p) }
Liquid::Spec::ClassRegistry.register("ThingWithToLiquid") { |p| ThingWithToLiquid.new(p) }
Liquid::Spec::ClassRegistry.register("ThingWithValue") { |p| ThingWithValue.new(p) }
Liquid::Spec::ClassRegistry.register("BooleanDrop") { |p| BooleanDrop.new(p) }
Liquid::Spec::ClassRegistry.register("IntegerDrop") { |p| IntegerDrop.new(p) }
Liquid::Spec::ClassRegistry.register("StringDrop") { |p| StringDrop.new(p) }
Liquid::Spec::ClassRegistry.register("ErrorDrop") { |p| ErrorDrop.new(p) }
Liquid::Spec::ClassRegistry.register("SettingsDrop") { |p| SettingsDrop.new(p) }
Liquid::Spec::ClassRegistry.register("CustomToLiquidDrop") { |p| CustomToLiquidDrop.new(p) }
Liquid::Spec::ClassRegistry.register("HashWithCustomToS") { |p| HashWithCustomToS.new(p) }
Liquid::Spec::ClassRegistry.register("HashWithoutCustomToS") { |p| HashWithoutCustomToS.new(p) }
Liquid::Spec::ClassRegistry.register("StubFileSystem") { |p| StubFileSystem.new(p) }
Liquid::Spec::ClassRegistry.register("StubTemplateFactory") { |p| StubTemplateFactory.new(p) }
Liquid::Spec::ClassRegistry.register("StubExceptionRenderer") { |p| StubExceptionRenderer.new(p) }
Liquid::Spec::ClassRegistry.register("LoaderDrop") { |p| LoaderDrop.new(p) }
Liquid::Spec::ClassRegistry.register("ArrayDrop") { |p| ArrayDrop.new(p) }

# Range - special handling for array format [start, end]
Liquid::Spec::ClassRegistry.register("Range") { |p| Range.new(p[0], p[1]) }

# Returns the Liquid::Drop class itself (for edge case tests)
Liquid::Spec::ClassRegistry.register("LiquidDropClass") { |_p| Liquid::Drop }
