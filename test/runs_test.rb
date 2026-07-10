# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "liquid/spec/cli/bench"
require "liquid/spec/cli/runs"

class RunsTest < Minitest::Test
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
end
