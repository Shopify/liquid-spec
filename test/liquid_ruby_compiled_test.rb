# frozen_string_literal: true

require "test_helper"
require "liquid/spec/deps/liquid_ruby"
require "liquid/spec/adapter/liquid_ruby_compiled"
require "liquid/spec/assertions"

# Add blank?/present? if ActiveSupport is not available
unless Object.method_defined?(:blank?)
  class Object
    def blank?
      respond_to?(:empty?) ? empty? : !self
    end

    def present?
      !blank?
    end
  end

  class NilClass
    def blank?
      true
    end
  end

  class FalseClass
    def blank?
      true
    end
  end

  class TrueClass
    def blank?
      false
    end
  end

  class String
    def blank?
      empty? || /\A[[:space:]]*\z/.match?(self)
    end

    def first(n = 1)
      self[0, n]
    end
  end
end

# Load compiled template support
require "liquid/compile"

class LiquidRubyCompiledTest < Minitest::Test
  include ::Liquid::Spec::Assertions.new(actual_adapter_proc: -> { Liquid::Spec::Adapter::LiquidRubyCompiled.new })

  Liquid::Spec::TestGenerator.define_on(self)
end
