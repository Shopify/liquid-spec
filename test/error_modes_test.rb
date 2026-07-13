# frozen_string_literal: true

require_relative "test_helper"
require "liquid/spec/cli/adapter_dsl"
require "liquid/spec/cli/runner"
require "liquid/spec/cli/matrix"

class ErrorModesTest < Minitest::Test
  include Liquid::Spec::TestHelpers

  def setup
    LiquidSpec.instance_variable_set(:@config, LiquidSpec::Configuration.new)
  end

  def teardown
    LiquidSpec.instance_variable_set(:@config, nil)
  end

  def test_defaults_to_strict2_and_raised_render_errors
    config = LiquidSpec.config

    assert_equal [:strict2], config.error_modes
    assert_equal [:raise], config.render_error_modes
    assert_includes config.missing_features, :strict_parsing
    assert_includes config.missing_features, :lax_parsing
    assert_includes config.missing_features, :inline_errors
    refute_includes config.missing_features, :strict2_parsing
  end

  def test_declarations_are_validated_and_canonicalized
    config = LiquidSpec.config
    config.error_modes = [:lax, :strict2, :strict]
    config.render_error_modes = [:inline, :raise]

    assert_equal [:strict2, :strict, :lax], config.error_modes
    assert_equal [:raise, :inline], config.render_error_modes
    assert_raises(ArgumentError) { config.error_modes = [] }
    assert_raises(ArgumentError) { config.error_modes = [:raise] }
    assert_raises(ArgumentError) { config.render_error_modes = [:strict] }
  end

  def test_unannotated_spec_runs_once_in_highest_supported_mode
    LiquidSpec.config.error_modes = [:lax, :strict, :strict2]
    variants = expand([create_spec])

    assert_equal [:strict2], variants.map(&:error_mode)
  end

  def test_unannotated_spec_uses_strict_when_it_is_highest_supported
    LiquidSpec.config.error_modes = [:lax, :strict]
    variants = expand([create_spec])

    assert_equal [:strict], variants.map(&:error_mode)
  end

  def test_explicit_multi_mode_spec_uses_highest_strict_mode_and_retains_lax
    LiquidSpec.config.error_modes = [:strict2, :strict, :lax]
    spec = create_spec(name: "portable", error_mode: [:lax, :strict2, :strict])
    variants = expand([spec])

    assert_equal [:strict2, :lax], variants.map(&:error_mode)
    assert_equal ["portable [error_mode=strict2]", "portable [error_mode=lax]"], variants.map(&:name)
  end

  def test_explicit_unsupported_mode_has_no_variant
    LiquidSpec.config.error_modes = [:strict2]

    assert_empty expand([create_spec(error_mode: :lax)])
  end

  def test_legacy_parse_feature_selects_its_declared_mode
    LiquidSpec.config.error_modes = [:strict2, :strict, :lax]
    spec = create_spec(features: [:lax_parsing])

    assert_equal [:lax], expand([spec]).map(&:error_mode)
  end

  def test_inline_error_specs_require_inline_render_support
    spec = create_spec(render_errors: true)

    assert_empty filter([spec])
    LiquidSpec.config.render_error_modes = [:raise, :inline]
    assert_equal 1, filter([spec]).size
  end

  def test_matrix_expands_explicit_modes_and_uses_strict2_for_ordinary_specs
    adapters = { "all" => Struct.new(:missing_features).new(Set.new) }
    ordinary = create_spec(name: "ordinary")
    portable = create_spec(name: "portable", error_mode: [:strict2, :strict])

    variants = Liquid::Spec::CLI::Matrix.send(:expand_error_mode_variants, [ordinary, portable], adapters)

    assert_equal [:strict2, :strict2], variants.map(&:error_mode)
    assert_equal "ordinary", variants.first.name
    assert_equal "portable [error_mode=strict2]", variants[1].name
  end

  private

  def expand(specs)
    Liquid::Spec::CLI::Runner.send(:expand_error_mode_variants, specs)
  end

  def filter(specs)
    Liquid::Spec::CLI::Runner.send(:filter_by_missing, specs, LiquidSpec.config.missing_features)
  end
end
