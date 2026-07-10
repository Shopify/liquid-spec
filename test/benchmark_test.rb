# frozen_string_literal: true

require_relative "test_helper"
require "liquid/spec/cli/benchmark"
require "liquid/spec/cli/fork_benchmark"
require "liquid/spec/suite"

class BenchmarkTest < Minitest::Test
  Benchmark = Liquid::Spec::CLI::Benchmark
  ForkBenchmark = Liquid::Spec::CLI::ForkBenchmark

  FakeSpec = Struct.new(:name)

  def test_shopify_shaped_benchmarks_use_only_portable_liquid
    suite = Liquid::Spec::Suite.find(:benchmarks)
    specs = Liquid::Spec::SpecLoader.load_suite(suite).select do |spec|
      %w[shopify_theme_full_page shopify_theme_product_page].include?(spec.name)
    end

    assert_equal 2, specs.size
    specs.each do |spec|
      source = ([spec.template] + spec.raw_filesystem.values).join("\n")
      assert_empty spec.features.grep(/shopify/), "#{spec.name} should not require Shopify features"
      refute_match(/\|\s*(?:asset_url|product_img_url|money|handle)\b/, source,
        "#{spec.name} should not use Shopify-only filters")
      refute_match(/\{%[-]?\s*(?:schema|style|section|paginate|form)\b/, source,
        "#{spec.name} should not use Shopify-only tags")
    end
  end

  def test_compact_preserves_sub_microsecond_precision_and_integer_ns
    value = {
      mean: 0.000_000_432_123,
      batches: [{ iterations: 5, elapsed_ns: 2_161 }],
      omitted: nil,
    }

    compacted = Benchmark.compact(value)

    assert_equal 0.000_000_432_123, compacted[:mean]
    assert_equal 2_161, compacted.dig(:batches, 0, :elapsed_ns)
    refute compacted.key?(:omitted)
  end

  def test_display_helpers_make_distributions_readable
    assert_equal "432 ns", Benchmark.fmt_metric(0.000_000_432)
    assert_equal "12.3 µs", Benchmark.fmt_metric(0.000_012_34)
    assert_equal "1.5 KiB", Benchmark.fmt_bytes(1536)
    assert_equal "▁▅█", Benchmark.sparkline([1, 2, 3])
    assert_equal ["steady", 0.02], Benchmark.stability(1.0, 0.02)
  end

  def test_timed_loop_retains_raw_nanosecond_batches
    stats = Benchmark.send(:timed_loop, 0.005) { 1 + 1 }

    assert_operator stats[:batches].size, :>, 0
    assert stats[:batches].all? { |sample| sample[:iterations].positive? }
    assert stats[:batches].all? { |sample| sample[:elapsed_ns].is_a?(Integer) && sample[:elapsed_ns].positive? }
    assert_equal stats[:iters], stats[:batches].sum { |sample| sample[:iterations] }
  end

  def test_fork_benchmark_propagates_child_errors
    spec = FakeSpec.new("failure")
    benchmark = ForkBenchmark.new([spec], samples: 1) do |_spec, _operation, _blob|
      raise ArgumentError, "adapter failed"
    end

    error = assert_raises(RuntimeError) { benchmark.measure(spec, artifact: false) }
    assert_includes error.message, "ArgumentError: adapter failed"
  ensure
    benchmark&.close
  end

  def test_fork_benchmark_isolates_every_workflow_sample
    spec = FakeSpec.new("isolated")
    process_local_calls = 0
    large_artifact = "a" * 1_000_000
    benchmark = ForkBenchmark.new([spec], samples: 3) do |_spec, operation, blob|
      case operation
      when :build_artifact
        large_artifact
      when :compile_render, :artifact_load_render
        process_local_calls += 1
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        output = "#{blob ? 'artifact' : 'source'}:#{process_local_calls}"
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started
        { elapsed_ns: [elapsed, 1].max, output: output }
      end
    end

    result = benchmark.measure(spec, artifact: true)

    assert_equal 3, result[:compile_render_samples_ns].size
    assert_equal 3, result[:artifact_load_render_samples_ns].size
    assert_equal "source:1", result[:compile_render_output]
    assert_equal "artifact:1", result[:artifact_load_render_output]
    assert_equal large_artifact.bytesize, result[:artifact_bytes]
  ensure
    benchmark&.close
  end
end
