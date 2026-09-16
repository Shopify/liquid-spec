# frozen_string_literal: true

require_relative "test_helper"
require "liquid/spec/feature_coverage"

class FeatureCoverageTest < Minitest::Test
  FeatureCoverage = Liquid::Spec::FeatureCoverage

  def test_exact_baseline_passes_with_known_orphans
    result = check(orphans: %i[shopify_blank shopify_filters], baseline: %i[shopify_blank shopify_filters])

    assert result.success?
    assert_equal %i[shopify_blank shopify_filters], result.known_orphans
    assert_empty result.new_orphans
    assert_empty result.stale_baseline
  end

  def test_new_orphan_fails
    result = check(orphans: %i[shopify_blank shopify_filters], baseline: [:shopify_blank])

    refute result.success?
    assert_equal [:shopify_filters], result.new_orphans
    assert_empty result.stale_baseline
  end

  def test_stale_baseline_entry_fails
    result = check(orphans: [:shopify_blank], baseline: %i[shopify_blank shopify_filters])

    refute result.success?
    assert_empty result.new_orphans
    assert_equal [:shopify_filters], result.stale_baseline
  end

  private

  def check(orphans:, baseline:)
    adapter_missing = { "reference.rb" => Set.new(orphans) }
    FeatureCoverage.check(
      spec_tags: orphans + [:covered],
      adapter_missing: adapter_missing,
      baseline: baseline,
    )
  end
end
