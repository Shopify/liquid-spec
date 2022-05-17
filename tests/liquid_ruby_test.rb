require "test_helper"
require "liquid/spec/deps/liquid_ruby"

class LiquidRubyTest < MiniTest::Test
end

Liquid::Spec::TestGenerator.generate(
  LiquidRubyTest,
  Liquid::Spec.all_sources,
  Liquid::Spec::Adapter::LiquidRuby.new,
)
