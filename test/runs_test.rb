# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "liquid/spec/cli/bench"
require "liquid/spec/cli/runs"

class RunsTest < Minitest::Test
  def test_default_builtin_adapters_exclude_legacy_liquid_c
    paths = Liquid::Spec::CLI::Runs.default_builtin_adapter_paths
    names = paths.map { |path| File.basename(path, ".rb") }

    assert_includes names, "liquid_ruby"
    assert_includes names, "json_rpc_ruby_liquid"
    refute_includes names, "liquid_c"
    refute_includes names, "liquid_c_strict"

    runs = Liquid::Spec::CLI::Runs.new
    runs.add_all_builtin_adapters
    assert_equal names.sort, runs.adapter_names.sort
  end

  def test_legacy_liquid_c_adapter_remains_explicitly_addressable
    runs = Liquid::Spec::CLI::Runs.new
    runs.add_adapter("liquid_c")

    assert_equal ["liquid_c"], runs.adapter_names
  end

  def test_classifies_adapters_and_detects_mixed_benchmark_transports
    Dir.mktmpdir do |dir|
      inline_path = File.join(dir, "inline.rb")
      json_rpc_path = File.join(dir, "rpc.rb")
      File.write(inline_path, "LiquidSpec.compile { |ctx, source, options| source }\n")
      File.write(json_rpc_path, 'require "liquid/spec/json_rpc/adapter"')

      runs = Liquid::Spec::CLI::Runs.new
      runs.add_adapter(inline_path)
      runs.add_adapter(json_rpc_path)

      assert_equal [:inline, :json_rpc], runs.adapters.map(&:transport)
      assert runs.mixed_transports?

      _stdout, stderr = capture_io do
        Liquid::Spec::CLI::Bench.warn_mixed_transport_comparison(runs)
      end
      assert_includes stderr, "compares inline and JSON-RPC adapters"
      assert_includes stderr, "Inline:   inline"
      assert_includes stderr, "JSON-RPC: rpc"
    end
  end

  def test_bench_subprocess_uses_current_ruby_without_the_gem_development_bundle
    adapter = File.expand_path("../examples/liquid_ruby.rb", __dir__)
    command = Liquid::Spec::CLI::Bench.send(:build_cmd, adapter, [])

    assert_equal RbConfig.ruby, command.first
    refute_includes command, "bundle"
    assert_includes command, adapter
  end

  def test_bench_rejects_failed_or_silent_adapter_subprocesses
    failed = fake_status(success: false, exitstatus: 7)
    error = assert_raises(RuntimeError) do
      Liquid::Spec::CLI::Bench.send(:validate_adapter_subprocess!, "broken", failed, { type: "run_metadata" })
    end
    assert_includes error.message, "broken exited with status 7"

    successful = fake_status(success: true, exitstatus: 0)
    error = assert_raises(RuntimeError) do
      Liquid::Spec::CLI::Bench.send(:validate_adapter_subprocess!, "silent", successful, nil)
    end
    assert_includes error.message, "silent produced no run metadata"
  end

  def test_same_transport_does_not_warn
    Dir.mktmpdir do |dir|
      first = File.join(dir, "first.rb")
      second = File.join(dir, "second.rb")
      File.write(first, "# inline")
      File.write(second, "# inline")

      runs = Liquid::Spec::CLI::Runs.new
      runs.add_adapter(first)
      runs.add_adapter(second)

      refute runs.mixed_transports?
      _stdout, stderr = capture_io do
        Liquid::Spec::CLI::Bench.warn_mixed_transport_comparison(runs)
      end
      assert_empty stderr
    end
  end

  private

  def fake_status(success:, exitstatus:)
    Object.new.tap do |status|
      status.define_singleton_method(:success?) { success }
      status.define_singleton_method(:signaled?) { false }
      status.define_singleton_method(:exitstatus) { exitstatus }
    end
  end
end
