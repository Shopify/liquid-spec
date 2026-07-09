# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "liquid/spec/cli/init"

class InitTest < Minitest::Test
  def test_generated_ruby_adapter_uses_context_to_pass_compiled_template
    source = generated_adapter(:basic)

    assert_includes source, "LiquidSpec.compile do |ctx, source, options|"
    assert_includes source, "LiquidSpec.render do |ctx, assigns, options|"
    assert_includes source, "ctx[:template].render(assigns"
    refute_includes source, "LiquidSpec.render do |ctx, template, assigns, options|"
    assert_valid_ruby(source)
  end

  def test_generated_json_rpc_adapter_uses_context_to_pass_template_id
    source = generated_adapter(:json_rpc)

    assert_includes source, "ctx[:template_id] = ctx[:adapter].compile(source, options)"
    assert_includes source, "LiquidSpec.render do |ctx, assigns, options|"
    assert_includes source, "ctx[:adapter].render(ctx[:template_id], assigns, options)"
    refute_includes source, "LiquidSpec.render do |ctx, template_id, assigns, options|"
    assert_valid_ruby(source)
  end

  def test_generated_liquid_ruby_adapter_uses_context_to_pass_compiled_template
    source = generated_adapter(:liquid_ruby)

    assert_includes source, "ctx[:template] = Liquid::Template.parse(source, **options)"
    assert_includes source, "LiquidSpec.render do |ctx, assigns, options|"
    assert_includes source, "ctx[:template].render(context)"
    refute_includes source, "LiquidSpec.render do |ctx, template, assigns, options|"
    assert_valid_ruby(source)
  end

  def test_combined_agent_guide_covers_both_adapters_without_narrowing_the_ramp
    guide = Liquid::Spec::CLI::Init.agents_md_content(
      "liquid_adapter_jsonrpc.rb",
      json_rpc: true,
      both: true
    )

    assert_includes guide, "## The Adapter Pattern (Ruby)"
    assert_includes guide, "## JSON-RPC Protocol (Non-Ruby Implementations)"
    assert_includes guide, "liquid-spec run liquid_adapter_jsonrpc.rb"
    refute_includes guide, ["-s", "basics"].join(" ")
  end

  private

  def generated_adapter(type)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "adapter.rb")
      capture_io { Liquid::Spec::CLI::Init.generate_adapter(path, type) }
      return File.read(path)
    end
  end

  def assert_valid_ruby(source)
    RubyVM::InstructionSequence.compile(source)
  rescue SyntaxError => error
    flunk "generated adapter is not valid Ruby: #{error.message}"
  end
end
