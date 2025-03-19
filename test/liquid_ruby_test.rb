# frozen_string_literal: true

require "test_helper"
require "liquid/spec/deps/liquid_ruby"
require "liquid/spec/adapter/liquid_ruby"
require "liquid/spec/assertions"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/access"

class LiquidRubyTest < Minitest::Test
  include ::Liquid::Spec::Assertions.new(actual_adapter_proc: -> { Liquid::Spec::Adapter::LiquidRuby.new })

  Liquid::Spec::TestGenerator.define_on(self)
end
