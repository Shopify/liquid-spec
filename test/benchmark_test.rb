# frozen_string_literal: true

require_relative "test_helper"
require "liquid/spec/cli/benchmark"
require "liquid/spec/suite"

class BenchmarkTest < Minitest::Test
  Benchmark = Liquid::Spec::CLI::Benchmark

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

  def test_workflow_samples_are_atomic_and_stay_in_process
    process_ids = []
    rendered_templates = []
    template = nil

    result = Benchmark.send(
      :measure_workflows,
      compile_proc: -> { process_ids << Process.pid; template = :source },
      render_proc: ->(_env) { process_ids << Process.pid; rendered_templates << template },
      env_proc: -> { {} },
      load_proc: ->(blob) { process_ids << Process.pid; template = blob },
      blob: :artifact,
    )

    assert_equal Benchmark::WORKFLOW_SAMPLES, result[:compile_render_samples_ns].size
    assert_equal Benchmark::WORKFLOW_SAMPLES, result[:artifact_load_render_samples_ns].size
    assert_equal [:source, :artifact], rendered_templates.uniq
    assert_equal [Process.pid], process_ids.uniq
    assert_equal "same_process_compile_each_sample", result[:compile_render_freshness]
    assert_equal "same_process_load_each_sample", result[:artifact_load_render_freshness]
  end
end
