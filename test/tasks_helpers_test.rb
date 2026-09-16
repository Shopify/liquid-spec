# frozen_string_literal: true

require_relative "test_helper"
require "date"
require "tmpdir"
require "yaml"
require_relative "../tasks/helpers"

class TasksHelpersTest < Minitest::Test
  def with_formatted_specs(capture, metadata: nil, default_complexity: nil)
    Dir.mktmpdir("liquid-spec-helper-test") do |dir|
      capture_path = File.join(dir, "capture.yml")
      output_path = File.join(dir, "specs.yml")
      File.write(capture_path, YAML.dump(capture))

      Helpers.format_and_write_specs(
        capture_path,
        output_path,
        metadata: metadata,
        default_complexity: default_complexity,
      )
      yield YAML.safe_load_file(output_path), Liquid::Spec::SpecLoader.load_file(output_path)
    end
  end

  def test_format_preserves_explicit_features_when_adding_inferred_ruby_features
    capture = [{
      "name" => "preserves_features",
      "template" => "{{ range }}",
      "expected" => "1..5",
      "features" => ["core"],
      "environment" => { "range" => { "instantiate:Range:" => [1, 5] } },
    }]

    with_formatted_specs(capture) do |document, _specs|
      assert_equal ["core", "ruby_drops"], document.first.fetch("features")
    end
  end

  def test_format_preserves_explicit_and_file_metadata_complexity
    capture = [
      { "name" => "explicit_complexity", "template" => "a", "expected" => "a", "complexity" => 321 },
      { "name" => "metadata_complexity", "template" => "b", "expected" => "b" },
    ]

    with_formatted_specs(capture, metadata: { "complexity" => 777 }, default_complexity: 1000) do |document, specs|
      assert_equal 777, document.fetch("_metadata").fetch("complexity")
      assert_equal 321, document.fetch("specs").first.fetch("complexity")
      refute document.fetch("specs").last.key?("complexity")
      assert_equal [321, 777], specs.map(&:complexity)
    end
  end

  def test_format_normalizes_symbol_complexity_metadata
    capture = [
      { "name" => "explicit_complexity", "template" => "a", "expected" => "a", "complexity" => 321 },
      { "name" => "metadata_complexity", "template" => "b", "expected" => "b" },
    ]

    with_formatted_specs(capture, metadata: { complexity: 777 }, default_complexity: 1000) do |document, specs|
      assert_equal 777, document.fetch("_metadata").fetch("complexity")
      refute document.fetch("_metadata").key?(:complexity)
      refute document.fetch("specs").last.key?("complexity")
      assert_equal [321, 777], specs.map(&:complexity)
    end
  end

  def test_format_string_minimum_complexity_metadata_blocks_per_spec_default
    assert_metadata_complexity("minimum_complexity" => 777)
  end

  def test_format_symbol_minimum_complexity_metadata_blocks_per_spec_default
    assert_metadata_complexity(minimum_complexity: 777)
  end

  def test_format_applies_an_opt_in_default_only_to_missing_complexity
    capture = [
      { "name" => "explicit_complexity", "template" => "a", "expected" => "a", "complexity" => 321 },
      { "name" => "default_complexity", "template" => "b", "expected" => "b" },
    ]

    with_formatted_specs(capture, default_complexity: 1000) do |document, _specs|
      complexities = document.to_h { |spec| [spec.fetch("name"), spec.fetch("complexity")] }
      assert_equal 321, complexities.fetch("explicit_complexity")
      assert_equal 1000, complexities.fetch("default_complexity")
    end
  end

  private

  def assert_metadata_complexity(metadata)
    capture = [
      { "name" => "explicit_complexity", "template" => "a", "expected" => "a", "complexity" => 321 },
      { "name" => "metadata_complexity", "template" => "b", "expected" => "b" },
    ]

    with_formatted_specs(capture, metadata: metadata, default_complexity: 1000) do |document, specs|
      assert_equal 777, document.fetch("_metadata").fetch("minimum_complexity")
      refute document.fetch("_metadata").key?(:minimum_complexity)
      refute document.fetch("specs").last.key?("complexity")
      assert_equal [321, 777], specs.map(&:complexity)
    end
  end
end
