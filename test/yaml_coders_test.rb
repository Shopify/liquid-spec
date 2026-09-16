# frozen_string_literal: true

require_relative "test_helper"
require "liquid"
require "liquid/spec/deps/liquid_ruby"

class YamlCodersTest < Minitest::Test
  include Liquid::Spec::TestHelpers

  def test_range_capture_round_trips_inclusive_exclusive_and_endless_ranges
    {
      "inclusive" => (1..5),
      "exclusive" => (1...5),
      "endless" => (1..),
    }.each do |name, range|
      captured = YAML.safe_load(YAML.dump({ "range" => range }))
      instantiated = create_spec(raw_environment: captured).instantiate_environment.fetch("range")

      assert_equal range, instantiated
      assert_equal range.exclude_end?, instantiated.exclude_end?
      assert_equal range.begin, instantiated.begin
      range.end.nil? ? assert_nil(instantiated.end) : assert_equal(range.end, instantiated.end)
    end
  end

  def test_inclusive_range_capture_keeps_the_historical_two_item_encoding
    captured = YAML.safe_load(YAML.dump({ "range" => (1..5) }))

    assert_equal [1, 5], captured.fetch("range").fetch("instantiate:Range:")
  end

  def test_exclusive_range_capture_appends_the_exclusive_flag
    captured = YAML.safe_load(YAML.dump({ "range" => (1...5) }))

    assert_equal [1, 5, true], captured.fetch("range").fetch("instantiate:Range:")
  end
end
