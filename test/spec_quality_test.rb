# frozen_string_literal: true

require "liquid"
require_relative "test_helper"

class SpecQualityTest < Minitest::Test
  EARLY_HINT_CEILING = 220
  RESOURCE_LIMIT_FLOOR = 500
  COMPLEXITY_CEILING = 1000

  def all_specs
    Liquid::Spec::Suite.all.flat_map do |suite|
      Liquid::Spec::SpecLoader.load_suite(suite).map { |spec| [suite, spec] }
    end
  end

  def test_complexity_scores_do_not_exceed_ceiling
    offenders = all_specs.filter_map do |suite, spec|
      complexity = spec.complexity || suite.minimum_complexity || COMPLEXITY_CEILING
      next if complexity <= COMPLEXITY_CEILING

      "#{spec.source_file}:#{spec.line_number}: #{spec.name} complexity=#{complexity}"
    end

    assert_empty offenders, "Complexity scores must be <= #{COMPLEXITY_CEILING}:\n#{offenders.join("\n")}"
  end

  def test_specs_through_early_core_ramp_have_effective_hints
    offenders = all_specs.filter_map do |suite, spec|
      complexity = spec.complexity || suite.minimum_complexity || COMPLEXITY_CEILING
      next if complexity > EARLY_HINT_CEILING
      next unless spec.effective_hint.to_s.strip.empty?

      "#{spec.source_file}:#{spec.line_number}: [#{complexity}] #{spec.name}"
    end

    assert_empty offenders, "Specs with complexity <= #{EARLY_HINT_CEILING} need hints:\n#{offenders.join("\n")}"
  end

  def test_resource_limit_specs_do_not_appear_in_beginner_ramp
    offenders = all_specs.filter_map do |suite, spec|
      next if spec.raw_resource_limits.nil? || spec.raw_resource_limits.empty?

      complexity = spec.complexity || suite.minimum_complexity || COMPLEXITY_CEILING
      next if complexity >= RESOURCE_LIMIT_FLOOR

      "#{spec.source_file}:#{spec.line_number}: [#{complexity}] #{spec.name}"
    end

    assert_empty offenders, "Resource-limit specs should be complexity >= #{RESOURCE_LIMIT_FLOOR}:\n#{offenders.join("\n")}"
  end
end
