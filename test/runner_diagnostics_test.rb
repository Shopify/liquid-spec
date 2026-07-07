# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tempfile"

class RunnerDiagnosticsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BIN = File.join(ROOT, "bin", "liquid-spec")
  FIXTURES = File.expand_path("fixtures/adapters", __dir__)

  def run_liquid_spec(adapter, *args)
    cmd = [
      RbConfig.ruby,
      "-I#{File.join(ROOT, "lib")}",
      BIN,
      File.join(FIXTURES, adapter),
      *args,
    ]
    stdout, stderr, status = Open3.capture3(*cmd, chdir: ROOT)
    [stdout, stderr, status.exitstatus]
  end

  def test_json_summary_includes_failures_and_passed_specs_when_requested
    stdout, stderr, status = run_liquid_spec(
      "source_echo_adapter.rb",
      "-n", "^empty_template$|^literal_passthrough$|^object_string_literal$",
      "--json",
      "--list-passed",
      "--max-failures", "2"
    )

    assert_equal 1, status
    assert_equal "", stderr

    payload = JSON.parse(stdout)
    assert_equal "fail", payload.fetch("status")
    assert_equal 2, payload.fetch("totals").fetch("passed")
    assert_equal 1, payload.fetch("totals").fetch("failed")
    assert_equal 0, payload.fetch("totals").fetch("errors")
    # Highest complexity level PRESENT in the run below the first failure
    # (levels here: 0, 1, then the failing 5) — not first_failure - 1.
    assert_equal 1, payload.fetch("max_complexity_reached")

    assert_equal ["object_string_literal"], payload.fetch("failures").map { |f| f.fetch("name") }
    assert_equal ["empty_template", "literal_passthrough"], payload.fetch("passed").map { |f| f.fetch("name") }
  end

  def test_list_passed_plain_output_lists_complexity_and_source
    stdout, _stderr, status = run_liquid_spec(
      "source_echo_adapter.rb",
      "-n", "^empty_template$|^literal_passthrough$|^object_string_literal$",
      "--list-passed",
      "--max-failures", "1"
    )

    assert_equal 1, status
    assert_includes stdout, "Passed specs:"
    assert_includes stdout, "[0] Basics :: empty_template (specs/basics/specs.yml)"
    assert_includes stdout, "[1] Basics :: literal_passthrough (specs/basics/specs.yml)"
    refute_includes stdout, "[5] Basics :: object_string_literal"
  end

  def test_always_empty_adapter_passes_empty_outputs_but_does_not_advance_ramp
    stdout, _stderr, status = run_liquid_spec(
      "empty_adapter.rb",
      "--json",
      "--list-passed",
      "--max-failures", "1"
    )

    assert_equal 1, status
    payload = JSON.parse(stdout)
    assert_operator payload.fetch("totals").fetch("passed"), :>, 1
    assert_equal 0, payload.fetch("max_complexity_reached")
    assert_includes payload.fetch("passed").map { |f| f.fetch("name") }, "empty_template"
    assert_includes payload.fetch("failures").map { |f| f.fetch("name") }, "literal_passthrough"
  end

  def test_always_raise_adapter_shows_error_and_hint_at_start_of_ramp
    stdout, _stderr, status = run_liquid_spec(
      "raise_compile_adapter.rb",
      "-n", "^empty_template$",
      "--max-failures", "1"
    )

    assert_equal 1, status
    assert_includes stdout, "Error:    SyntaxError: dumb compile boom"
    assert_includes stdout, "Hint: START HERE"
    assert_includes stdout, "Complexity level cleared: 0"
  end

  def test_plain_output_starts_with_complexity_level_summary_and_omits_suite_preamble
    stdout, _stderr, status = run_liquid_spec(
      "source_echo_adapter.rb",
      "-n", "^empty_template$|^literal_passthrough$|^object_string_literal$",
      "--max-failures", "1"
    )

    assert_equal 1, status
    assert stdout.start_with?("Next best specs to work on:"), "stdout should start with the failure list, got:\n#{stdout[0,120]}"
    assert_match(/Complexity level cleared: \d+ of \d+, \d+ passes, \d+ failures\./, stdout)
    refute_includes stdout, "Missing features:"
    refute_includes stdout, "Known failures:"
    # no per-suite progress lines leak into default stdout
    refute_match(/\.{40}/, stdout)
  end

  def test_plain_summary_includes_skipped_count_when_specs_are_filtered
    Tempfile.create(["liquid-spec-skipped", ".yml"]) do |file|
      file.write(<<~YML)
        ---
        - name: normal_failure
          template: "{{ nope }}"
          expected: "not source echo"
          complexity: 10
          hint: "Normal failing spec."
        - name: ruby_types_skipped
          template: "{{ x }}"
          expected: "y"
          complexity: 10
          features: [ruby_types]
          hint: "Skipped because adapter opts out of ruby_types."
      YML
      file.close

      stdout, _stderr, status = run_liquid_spec(
        "source_echo_adapter.rb",
        "--add-specs", file.path,
        "-n", "/^(normal_failure|ruby_types_skipped)$/",
        "--max-failures", "1"
      )

      assert_equal 1, status
      assert_includes stdout, "1) [c=10] normal_failure"
      refute_includes stdout, "ruby_types_skipped"
      assert_match(/, 1 skipped\./, stdout)
    end
  end

  def test_printed_failures_are_lowest_complexity_across_prioritized_and_suite_specs
    Tempfile.create(["liquid-spec-high-complexity", ".yml"]) do |file|
      file.write(<<~YML)
        ---
        - name: high_added_failure
          template: "{{ nope }}"
          expected: "not source echo"
          complexity: 1000
          hint: "High-complexity added spec used to verify failure sorting."
      YML
      file.close

      stdout, _stderr, status = run_liquid_spec(
        "source_echo_adapter.rb",
        "--add-specs", file.path,
        "-n", "/^(object_string_literal|high_added_failure)$/",
        "--max-failures", "1"
      )

      assert_equal 1, status
      assert stdout.start_with?("Next best specs to work on:"), "stdout should start with the failure list, got:\n#{stdout[0,120]}"
      refute_includes stdout, "Prioritized Specs"
      assert_includes stdout, "1) [c=5] object_string_literal"
      refute_includes stdout, "[c=1000] high_added_failure"
      assert_includes stdout, "(... 1 more failures not shown due to --max-failures 1 ...)"
      assert_includes stdout, "Failures are ordered by complexity. Solve above failures first."
    end
  end
end
