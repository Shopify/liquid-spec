# frozen_string_literal: true

require_relative "test_helper"

class GemspecTest < Minitest::Test
  GEMSPEC_PATH = File.expand_path("../liquid-spec.gemspec", __dir__)

  def test_required_runtime_dependencies_are_declared
    gemspec = Gem::Specification.load(GEMSPEC_PATH)
    dependencies = gemspec.runtime_dependencies.to_h { |dependency| [dependency.name, dependency.requirement] }

    assert_equal Gem::Requirement.new(">= 7.0", "< 9"), dependencies.fetch("activesupport")
    assert_equal Gem::Requirement.new("~> 0.3.0"), dependencies.fetch("base64")
    assert_equal Gem::Requirement.new("~> 5.13"), dependencies.fetch("liquid")
  end
end
