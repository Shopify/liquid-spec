# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

class ParseModeAnnotationVerifierTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  VERIFIER = File.join(ROOT, "scripts/verifiers/parse_mode_annotation.rb")

  def test_checks_parse_mode_even_when_environment_uses_instantiated_objects
    yaml = <<~YAML
      specs:
      - name: dynamic_root_with_drop
        template: "{{ [list[settings.zero]] }}"
        environment:
          settings:
            "instantiate:SettingsDrop:": { settings: { zero: 0 } }
        expected: ""
        complexity: 180
    YAML

    status, output = run_verifier(yaml)

    refute status.success?
    assert_includes output, "dynamic_root_with_drop"
    assert_includes output, "accepted differently across parse modes"
  end

  def test_accepts_explicit_mode_for_instantiated_object_spec
    yaml = <<~YAML
      specs:
      - name: dynamic_root_with_drop
        template: "{{ [list[settings.zero]] }}"
        error_mode: [lax, strict]
        environment:
          settings:
            "instantiate:SettingsDrop:": { settings: { zero: 0 } }
        expected: ""
        complexity: 180
    YAML

    status, output = run_verifier(yaml)

    assert status.success?, output
    assert_includes output, "OK: all unannotated specs"
  end

  private

  def run_verifier(yaml)
    Dir.mktmpdir do |dir|
      specs = File.join(dir, "specs", "fixture")
      FileUtils.mkdir_p(specs)
      File.write(File.join(specs, "specs.yml"), yaml)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        "-I#{File.join(ROOT, "lib")}",
        VERIFIER,
        chdir: dir
      )
      return [status, stdout + stderr]
    end
  end
end
