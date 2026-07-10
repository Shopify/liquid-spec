# frozen_string_literal: true

require_relative "test_helper"
require "liquid/spec/cli/adapter_dsl"
require "liquid/spec/cli/runner"

class AdapterArtifactTest < Minitest::Test
  Runner = Liquid::Spec::CLI::Runner

  def setup
    LiquidSpec.reset!
  end

  def teardown
    LiquidSpec.reset!
  end

  def test_benchmark_warns_when_both_artifact_hooks_are_missing
    _stdout, stderr = capture_io do
      Runner.send(:warn_missing_artifact_protocol, "example")
    end

    assert_includes stderr, "does not declare compiled-artifact support"
    assert_includes stderr, "load+first-render benchmarks will be omitted"
  end

  def test_benchmark_identifies_an_incomplete_artifact_protocol
    LiquidSpec.dump_artifact { |_ctx| "bytes" }

    _stdout, stderr = capture_io do
      Runner.send(:warn_missing_artifact_protocol, "example")
    end

    assert_includes stderr, "declares only half"
    assert_includes stderr, "LiquidSpec.load_artifact"
    refute LiquidSpec.artifact_capable?
  end

  def test_json_rpc_adapter_keeps_transport_inclusive_timer_scope
    refute Runner.send(:json_rpc_adapter?)

    LiquidSpec.ctx[:adapter] = Liquid::Spec::JsonRpc::Adapter.allocate
    assert Runner.send(:json_rpc_adapter?)
  end

  def test_complete_artifact_protocol_is_silent
    LiquidSpec.dump_artifact { |_ctx| "bytes" }
    LiquidSpec.load_artifact { |ctx, bytes, _options| ctx[:template] = bytes }

    _stdout, stderr = capture_io do
      Runner.send(:warn_missing_artifact_protocol, "example")
    end

    assert_empty stderr
    assert LiquidSpec.artifact_capable?
  end
end
