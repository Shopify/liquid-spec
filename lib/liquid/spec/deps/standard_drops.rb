# frozen_string_literal: true

# Standard Test Drop Library
#
# A portable set of drop classes for testing Liquid drop behavior.
# Each drop has deterministic, documented behavior that can be replicated
# natively by any Liquid implementation. See docs/test_drops.md.
#
# These drops replace the Ruby-specific drop classes (ToSDrop, BooleanDrop,
# IntegerDrop, etc.) for cross-implementation testing. No RPC callbacks
# needed — the behavior is a known function of the input.

# BooleanDrop — wraps a boolean value
#   to_liquid_value returns the boolean
#   truthy/falsy follows the value
class StandardBooleanDrop < Liquid::Drop
  def initialize(params = {})
    @value = params["value"] || params[:value] || false
  end

  def to_liquid_value
    @value
  end

  def to_s
    @value ? "true" : "false"
  end
end

# NumberDrop — wraps an integer
#   to_liquid_value returns the integer
#   filters see the raw integer
class StandardNumberDrop < Liquid::Drop
  def initialize(params = {})
    @value = params["value"] || params[:value] || 0
  end

  def to_liquid_value
    @value
  end
  def to_number
    @value
  end

  def to_s
    @value.to_s
  end
end

# StringDrop — wraps a string
#   to_liquid_value returns the string
class StandardStringDrop < Liquid::Drop
  include Comparable

  def initialize(params = {})
    @value = params["value"] || params[:value] || ""
  end

  def to_liquid_value
    @value
  end

  def to_s
    @value
  end

  def <=>(other)
    @value <=> other.to_s
  end
end

# MethodDrop — property access with deterministic transforms
#   drop.echo_N   → "N"   (identity)
#   drop.square_N → "N*N" (square)
#   drop.double_N → "N*2" (double)
#
# The property name encodes the operation and integer argument.
# The implementer parses op_N, applies the operation, returns the result as a string.
class StandardMethodDrop < Liquid::Drop
  def initialize(_params = {})
  end

  def invoke_drop(method_or_key)
    name = method_or_key.to_s
    if name =~ /^(echo|square|double)_(\d+)$/
      op = $1
      n = $2.to_i
      result = case op
               when "echo" then n
               when "square" then n * n
               when "double" then n * 2
               end
      return result.to_s
    end
    super
  end
  alias_method :[], :invoke_drop
end

# IndexDrop — bracket access
#   drop[0]      → "zero"   (int index → number word)
#   drop[1]      → "one"
#   drop[2]      → "two"
#   drop["foo"]  → "foo"    (string index → identity)
class StandardIndexDrop < Liquid::Drop
  NUMBER_WORDS = %w[zero one two three four five].freeze

  def initialize(_params = {})
  end

  def [](key)
    case key
    when Integer
      NUMBER_WORDS[key] || "unknown"
    when String
      key
    else
      "unknown"
    end
  end
end

# SequenceDrop — enumerable yielding "first", "second", "third"
#   drop.size → 3
#   drop.first → "first"
#   drop.last → "third"
#   {% for item in drop %}{{ item }}{% endfor %} → "firstsecondthird"
class StandardSequenceDrop < Liquid::Drop
  include Enumerable

  SEQUENCE = %w[first second third].freeze

  def initialize(_params = {})
  end

  def each(&block)
    SEQUENCE.each(&block)
  end

  def size
    SEQUENCE.size
  end

  def first
    SEQUENCE.first
  end

  def last
    SEQUENCE.last
  end
end

# NilDrop — to_liquid returns nil
#   renders as empty string, falsy
class StandardNilDrop < Liquid::Drop
  def initialize(_params = {})
  end

  def to_liquid
    nil
  end
end

# OpaqueDrop — no to_liquid_value, always truthy
#   renders via to_s → "opaque"
class StandardOpaqueDrop < Liquid::Drop
  def initialize(_params = {})
  end

  def to_s
    "opaque"
  end
end

# ErrorDrop — raises on any access
class StandardErrorDrop < Liquid::Drop
  def initialize(_params = {})
  end

  def invoke_drop(*)
    raise "ErrorDrop: access triggered an error"
  end
  alias_method :[], :invoke_drop
end

# Register all standard drops with the ClassRegistry
# Use "Standard" prefix in Ruby class names to avoid collision with legacy drops,
# but register under the portable names (BooleanDrop, NumberDrop, etc.)
STANDARD_DROPS = {
  "BooleanDrop" => StandardBooleanDrop,
  "NumberDrop" => StandardNumberDrop,
  "StringDrop" => StandardStringDrop,
  "MethodDrop" => StandardMethodDrop,
  "IndexDrop" => StandardIndexDrop,
  "SequenceDrop" => StandardSequenceDrop,
  "NilDrop" => StandardNilDrop,
  "OpaqueDrop" => StandardOpaqueDrop,
  "ErrorDrop" => StandardErrorDrop,
}.freeze

STANDARD_DROPS.each do |name, klass|
  Liquid::Spec::ClassRegistry.register(name) { |p| klass.new(p) }
end
