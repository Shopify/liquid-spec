# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "liquid/spec/cli/init"

class InitTest < Minitest::Test
  def test_generated_ruby_adapter_uses_context_to_pass_compiled_template
    source = generated_adapter(:basic)

    assert_includes source, "LiquidSpec.compile do |ctx, source, options|"
    assert_includes source, "LiquidSpec.render do |ctx, assigns, options|"
    assert_includes source, "ctx[:template].render(assigns"
    assert_includes source, "config.error_modes = [:strict2]"
    assert_includes source, "config.render_error_modes = [:raise]"
    refute_includes source, "LiquidSpec.render do |ctx, template, assigns, options|"
    assert_valid_ruby(source)
  end

  def test_generated_json_rpc_adapter_uses_context_to_pass_template_id
    source = generated_adapter(:json_rpc)

    assert_includes source, "ctx[:template_id] = ctx[:adapter].compile(source, options)"
    assert_includes source, "LiquidSpec.render do |ctx, assigns, options|"
    assert_includes source, "ctx[:adapter].render(ctx[:template_id], assigns, options)"
    assert_includes source, "config.error_modes = [:strict2]"
    assert_includes source, "config.render_error_modes = [:raise]"
    refute_includes source, "LiquidSpec.render do |ctx, template_id, assigns, options|"
    assert_valid_ruby(source)
  end

  def test_generated_liquid_ruby_adapter_uses_context_to_pass_compiled_template
    source = generated_adapter(:liquid_ruby)

    assert_includes source, "ctx[:template] = Liquid::Template.parse(source, **options)"
    assert_includes source, "LiquidSpec.render do |ctx, assigns, options|"
    assert_includes source, "ctx[:template].render(context)"
    assert_includes source, "config.error_modes = [:strict2, :strict, :lax]"
    assert_includes source, "config.render_error_modes = [:raise, :inline]"
    refute_includes source, "LiquidSpec.render do |ctx, template, assigns, options|"
    assert_valid_ruby(source)
  end

  def test_combined_agent_guide_covers_both_adapters_without_narrowing_the_ramp
    guide = Liquid::Spec::CLI::Init.agents_md_content(
      "specs/adapter-jsonrpc.rb",
      json_rpc: true,
      both: true,
      ruby_filename: "specs/adapter.rb"
    )

    assert_includes guide, "## The Adapter Pattern (Ruby)"
    assert_includes guide, "## JSON-RPC Protocol (Non-Ruby Implementations)"
    assert_includes guide, "Use `specs/adapter.rb`"
    assert_includes guide, "`specs/adapter-jsonrpc.rb`"
    assert_includes guide, "liquid-spec run specs/adapter-jsonrpc.rb"
    assert_includes guide, "liquid-spec tools fuzz specs/adapter-jsonrpc.rb"
    refute_includes guide, ["-s", "basics"].join(" ")
  end

  def test_default_init_writes_both_adapters_under_specs
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        capture_io { Liquid::Spec::CLI::Init.run([]) }

        assert File.exist?("specs/adapter.rb")
        assert File.executable?("specs/adapter.rb")
        assert File.exist?("specs/adapter-jsonrpc.rb")
        assert File.executable?("specs/adapter-jsonrpc.rb")
        assert File.exist?("AGENTS.md")
        assert_includes File.read("AGENTS.md"), "liquid-spec run specs/adapter-jsonrpc.rb"
      end
    end
  end

  def test_type_flag_without_filename_uses_nested_default_path
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        capture_io { Liquid::Spec::CLI::Init.run(["--jsonrpc"]) }

        assert File.exist?("specs/adapter-jsonrpc.rb")
        refute File.exist?("specs/adapter.rb")
      end
    end
  end

  def test_collision_defaults_to_not_overwriting_different_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "adapter.rb")
      File.write(path, "keep me")

      output, = with_stdin("\n") do
        capture_io { Liquid::Spec::CLI::Init.generate_adapter(path, :basic) }
      end

      assert_equal "keep me", File.read(path)
      assert_includes output, "Overwrite? [y/N]"
      assert_includes output, "Skipped #{path}"
    end
  end

  def test_collision_can_overwrite_different_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "adapter.rb")
      File.write(path, "replace me")

      output, = with_stdin("yes\n") do
        capture_io { Liquid::Spec::CLI::Init.generate_adapter(path, :basic) }
      end

      assert_includes File.read(path), "LiquidSpec.compile"
      assert File.executable?(path)
      assert_includes output, "Overwrote #{path}"
    end
  end

  def test_identical_collision_is_left_unchanged_without_prompt
    Dir.mktmpdir do |dir|
      path = File.join(dir, "adapter.rb")
      capture_io { Liquid::Spec::CLI::Init.generate_adapter(path, :basic) }

      output, = with_stdin("yes\n") do
        capture_io { Liquid::Spec::CLI::Init.generate_adapter(path, :basic) }
      end

      assert_includes output, "Unchanged #{path}"
      refute_includes output, "Overwrite?"
    end
  end

  private

  def generated_adapter(type)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "adapter.rb")
      capture_io { Liquid::Spec::CLI::Init.generate_adapter(path, type) }
      return File.read(path)
    end
  end

  def with_stdin(input)
    original_stdin = $stdin
    $stdin = StringIO.new(input)
    yield
  ensure
    $stdin = original_stdin
  end

  def assert_valid_ruby(source)
    RubyVM::InstructionSequence.compile(source)
  rescue SyntaxError => error
    flunk "generated adapter is not valid Ruby: #{error.message}"
  end
end
