# frozen_string_literal: true

require_relative "test_helper"
require "liquid"
require "tmpdir"
require "fileutils"

# Integration tests for error-pattern matching in spec YAML:
#   * multiple patterns (all must match)
#   * case-insensitive literal substring matching (string patterns)
#   * Regexp patterns (!ruby/regexp) used as-is, with metacharacters
#   * error class name matching
#   * !ruby/regexp allowed through the loader, !ruby/object still rejected
class ErrorPatternTest < Minitest::Test
  def with_temp_spec(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "spec.yml")
      File.write(path, content)
      yield path
    end
  end

  def test_loader_allows_ruby_regexp_tag
    with_temp_spec(<<~YAML) do |path|
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - !ruby/regexp /ZeroDivision|divided by/i
    YAML
      specs = Liquid::Spec::SpecLoader.load_yaml_file(path)
      assert_equal 1, specs.size
      patterns = specs.first.error_patterns(:render_error)
      assert_equal 1, patterns.size
      assert_kind_of Regexp, patterns[0]
      assert patterns[0].match?("Liquid error: divided by 0")
      assert patterns[0].match?("ZeroDivisionError")
      refute patterns[0].match?("something unrelated")
    end
  end

  def test_loader_rejects_ruby_object_tag
    with_temp_spec(<<~YAML) do |path|
      ---
      - name: t
        template: "{{ x }}"
        environment:
          o: !ruby/object:Object {}
    YAML
      err = assert_raises(RuntimeError) do
        Liquid::Spec::SpecLoader.load_yaml_file(path)
      end
      assert_match(/!ruby\/ tags which are not allowed/, err.message)
    end
  end

  def test_loader_mixed_regexp_and_string_patterns
    with_temp_spec(<<~YAML) do |path|
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - !ruby/regexp /ZeroDivision|divided by/i
            - divided by 0
    YAML
      specs = Liquid::Spec::SpecLoader.load_yaml_file(path)
      patterns = specs.first.error_patterns(:render_error)
      assert_equal 2, patterns.size
      assert patterns[0].match?("ZeroDivision")
      # String pattern is escaped + case-insensitive substring
      assert patterns[1].match?("DIVIDED BY 0")
    end
  end

  def test_run_spec_regexp_pattern_matches
    skip "liquid gem required" unless defined?(Liquid::Template)
    assert_spec_passes(<<~YAML)
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - !ruby/regexp /ZeroDivision|divided by/i
    YAML
  end

  def test_run_spec_regexp_pattern_non_match_fails
    skip "liquid gem required" unless defined?(Liquid::Template)
    refute_spec_passes(<<~YAML)
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - !ruby/regexp /this will not match/
    YAML
  end

  def test_run_spec_multiple_substring_patterns_all_match
    skip "liquid gem required" unless defined?(Liquid::Template)
    assert_spec_passes(<<~YAML)
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - divided
            - by 0
    YAML
  end

  def test_run_spec_multiple_substring_patterns_one_missing_fails
    skip "liquid gem required" unless defined?(Liquid::Template)
    refute_spec_passes(<<~YAML)
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - divided by 0
            - this substring is absent
    YAML
  end

  def test_run_spec_class_name_match
    # The reference liquid-ruby raises Liquid::ZeroDivisionError; matching the
    # class name as a substring ("ZeroDivisionError") should pass.
    skip "liquid gem required" unless defined?(Liquid::Template)
    assert_spec_passes(<<~YAML)
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - ZeroDivisionError
    YAML
  end

  def test_run_spec_class_name_non_match_fails
    skip "liquid gem required" unless defined?(Liquid::Template)
    refute_spec_passes(<<~YAML)
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - ArgumentError
    YAML
  end

  def test_run_spec_case_insensitive_substring
    skip "liquid gem required" unless defined?(Liquid::Template)
    assert_spec_passes(<<~YAML)
      ---
      - name: t
        template: "{{ 10 | divided_by: 0 }}"
        errors:
          render_error:
            - DIVIDED BY 0
    YAML
  end

  private

  def run_one_spec(spec_yaml)
    setup_liquid_ruby_adapter!
    Dir.mktmpdir do |dir|
      path = File.join(dir, "spec.yml")
      File.write(path, spec_yaml)
      specs = Liquid::Spec::SpecLoader.load_yaml_file(path)
      spec = specs.first
      require "liquid/spec/cli/runner"
      runner = Liquid::Spec::CLI::Runner
      # run_single_spec is a private class method; invoke it via send
      result = runner.send(:run_single_spec, spec, nil)
      result
    end
  end

  @adapter_loaded = false
  def setup_liquid_ruby_adapter!
    return if self.class.instance_variable_get(:@adapter_loaded)
    require "liquid"
    example = File.expand_path("../examples/liquid_ruby.rb", __dir__)
    load example
    self.class.instance_variable_set(:@adapter_loaded, true)
  end

  def assert_spec_passes(spec_yaml)
    result = run_one_spec(spec_yaml)
    assert_equal :pass, result[:status],
      "expected spec to pass but got #{result[:status]}: #{result.inspect}"
  end

  def refute_spec_passes(spec_yaml)
    result = run_one_spec(spec_yaml)
    refute_equal :pass, result[:status],
      "expected spec to NOT pass but it did: #{result.inspect}"
  end
end
