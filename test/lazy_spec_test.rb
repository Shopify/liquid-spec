# frozen_string_literal: true

require_relative "test_helper"

class LazySpecTest < Minitest::Test
  include Liquid::Spec::TestHelpers

  def test_basic_spec_creation
    spec = create_spec(
      name: "test_assign",
      template: "{% assign x = 1 %}{{ x }}",
      expected: "1"
    )

    assert_equal "test_assign", spec.name
    assert_equal "{% assign x = 1 %}{{ x }}", spec.template
    assert_equal "1", spec.expected
  end

  def test_validation_requires_name
    spec = create_spec(name: nil)
    refute spec.valid?
    assert_includes spec.validation_errors, "missing required field 'name'"
  end

  def test_validation_requires_template
    spec = create_spec(template: nil)
    refute spec.valid?
    assert_includes spec.validation_errors, "missing required field 'template'"
  end

  def test_validation_requires_expected_or_errors
    spec = create_spec(expected: nil, errors: {})
    refute spec.valid?
    assert_includes spec.validation_errors, "must have either 'expected', 'expected_pattern', or 'errors' (got neither)"
  end

  def test_validation_accepts_errors_without_expected
    spec = create_spec(expected: nil, errors: { "parse_error" => ["syntax"] })
    assert spec.valid?
  end

  def test_validation_unknown_error_keys
    spec = create_spec(errors: { "unknown_error" => ["test"] })
    refute spec.valid?
    assert spec.validation_errors.any? { |e| e.include?("unknown error type") }
  end

  def test_expects_parse_error
    spec = create_spec(errors: { "parse_error" => ["syntax error"] })
    assert spec.expects_parse_error?
    refute spec.expects_render_error?
  end

  def test_expects_render_error
    spec = create_spec(errors: { "render_error" => ["undefined"] })
    refute spec.expects_parse_error?
    assert spec.expects_render_error?
  end

  def test_error_patterns
    spec = create_spec(errors: { "parse_error" => ["syntax", "unexpected"] })
    patterns = spec.error_patterns(:parse_error)

    assert_equal 2, patterns.size
    assert patterns.all? { |p| p.is_a?(Regexp) }
    assert patterns[0].match?("Syntax Error")  # case insensitive
    assert patterns[1].match?("UNEXPECTED token")
  end

  def test_error_patterns_pass_regexp_through_unchanged
    # A Regexp pattern is used as-is (not escaped), so metacharacters work.
    regexp = /divided by \d+/i
    spec = create_spec(errors: { "render_error" => [regexp] })
    patterns = spec.error_patterns(:render_error)

    assert_equal 1, patterns.size
    assert_same regexp, patterns[0]
    assert patterns[0].match?("Liquid error: divided by 0")
    refute patterns[0].match?("divided by zero")
  end

  def test_error_patterns_mix_regexp_and_string
    spec = create_spec(errors: { "render_error" => [/ZeroDivision|divided by/i, "divided by 0"] })
    patterns = spec.error_patterns(:render_error)

    assert_equal 2, patterns.size
    assert patterns[0].is_a?(Regexp)
    assert patterns[0].match?("ZeroDivision")
    # String pattern is escaped + case-insensitive substring
    assert patterns[1].match?("DIVIDED BY 0")
  end

  def test_features
    spec = create_spec(features: [:shopify_tags, :shopify_filters])
    assert_equal [:shopify_tags, :shopify_filters], spec.features
  end

  def test_error_mode_adds_lax_parsing_feature
    spec = create_spec(error_mode: :lax)
    assert_includes spec.features, :lax_parsing
  end

  def test_error_mode_adds_strict_parsing_feature
    spec = create_spec(error_mode: :strict)
    assert_includes spec.features, :strict_parsing
  end

  def test_with_error_mode_creates_isolated_labeled_variant
    original = create_spec(error_mode: [:lax, :strict])
    variant = original.with_error_mode(:strict, label: true)

    assert_equal [:lax, :strict], original.error_modes
    assert_equal :strict, variant.error_mode
    assert_equal [:strict], variant.error_modes
    assert_equal "test_spec [error_mode=strict]", variant.name
    assert_includes variant.features, :strict_parsing
    refute_includes variant.features, :lax_parsing
  end

  def test_skipped_by_missing_features
    spec = create_spec(features: [:core, :shopify_tags])

    refute spec.skipped_by?([:shopify_filters])
    assert spec.skipped_by?([:shopify_tags])
    assert spec.skipped_by?([:core, :shopify_tags])
  end

  def test_skipped_by_empty_missing_features
    spec = create_spec(features: [:core, :shopify_tags, :shopify_filters])

    refute spec.skipped_by?([])
    assert spec.skipped_by?([:shopify_tags])
    assert spec.skipped_by?([:shopify_filters])
    refute spec.skipped_by?([:drops])
  end

  def test_location_with_file_and_line
    spec = create_spec(source_file: "specs/test.yml", line_number: 42)
    assert_equal "specs/test.yml:42", spec.location
  end

  def test_location_with_file_only
    spec = create_spec(source_file: "specs/test.yml", line_number: nil)
    assert_equal "specs/test.yml", spec.location
  end

  def test_location_falls_back_to_name
    spec = create_spec(source_file: nil, line_number: nil)
    assert_equal "test_spec", spec.location
  end

  def test_complexity_default
    spec = create_spec
    assert_equal 1000, spec.complexity
  end

  def test_complexity_custom
    spec = create_spec(complexity: 50)
    assert_equal 50, spec.complexity
  end

  def test_hint
    spec = create_spec(hint: "This requires ActiveSupport")
    assert_equal "This requires ActiveSupport", spec.effective_hint
  end

  def test_source_hint_fallback
    spec = create_spec(hint: nil, source_hint: "Source-level hint")
    assert_equal "Source-level hint", spec.effective_hint
  end

  def test_spec_hint_overrides_source_hint
    spec = create_spec(hint: "Spec hint", source_hint: "Source hint")
    assert_equal "Spec hint", spec.effective_hint
  end
end
