require "test_helper"
require "liquid/spec/deps/liquid_ruby"
require "liquid/spec/adapter/liquid_ruby"

class LiquidRubyTest < Minitest::Test
end

Liquid::Spec::TestGenerator.generate(
  LiquidRubyTest,
  Liquid::Spec.all_sources,
  Liquid::Spec::Adapter::LiquidRuby.new,
)
