# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class CliToolsTest < Minitest::Test
  def test_top_level_help_is_focused_on_four_core_commands_and_tools
    stdout, stderr, status = cli("help")

    assert status.success?, stderr
    assert_includes stdout, "Core commands:"
    %w[init docs run bench].each { |command| assert_match(/^  #{command}\b/, stdout) }
    assert_match(/^  tools COMMAND\b/, stdout)
    refute_match(/^  (eval|inspect|matrix|mutate|fuzz|stress)\b/, stdout)
  end

  def test_init_help_documents_nested_default_adapters
    stdout, stderr, status = cli("init", "--help")

    assert status.success?, stderr
    assert_includes stdout, "specs/adapter.rb"
    assert_includes stdout, "specs/adapter-jsonrpc.rb"
    assert_includes stdout, "defaults"
    assert_includes stdout, "No"
  end

  def test_tools_help_lists_secondary_commands
    stdout, stderr, status = cli("tools", "help")

    assert status.success?, stderr
    %w[inspect eval matrix test features report check mutate fuzz stress].each do |command|
      assert_match(/^  #{command}\b/, stdout)
    end
  end

  def test_nested_command_help_uses_canonical_path
    stdout, stderr, status = cli("tools", "eval", "--help")

    assert status.success?, stderr
    assert_includes stdout, "Usage: liquid-spec tools eval ADAPTER"
  end

  def test_legacy_tool_alias_routes_with_deprecation_warning
    stdout, stderr, status = cli("eval", "--help")

    assert status.success?
    assert_includes stdout, "Usage: liquid-spec tools eval ADAPTER"
    assert_includes stderr, "Deprecated: use `liquid-spec tools eval`"
  end

  def test_check_help_documents_all_verifiers
    stdout, stderr, status = cli("tools", "check", "--help")

    assert status.success?, stderr
    assert_includes stdout, "Run every verifier in scripts/verifiers"
  end

  private

  def cli(*args)
    root = File.expand_path("..", __dir__)
    Open3.capture3(
      RbConfig.ruby,
      "-I#{File.join(root, "lib")}",
      File.join(root, "bin", "liquid-spec"),
      *args
    )
  end
end
