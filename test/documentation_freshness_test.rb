# frozen_string_literal: true

require_relative "test_helper"
require "liquid/spec/suite"
require "liquid/spec/verifiers"

class DocumentationFreshnessTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DOCUMENTATION_FILES = Dir.glob(
    File.join(ROOT, "**", "{README,AGENTS}.md"),
    File::FNM_DOTMATCH
  ).sort.freeze

  STALE_PATTERNS = {
    /\bliquid_adapter(?:_jsonrpc)?\.rb\b/ => "pre-2.0 generated adapter filename",
    /\bliquid-spec (?:eval|inspect|matrix|report|features|mutate|fuzz|stress|check)\b/ =>
      "utility outside the `liquid-spec tools` namespace",
    /\bliquid-spec run [^\n]*--bench\b/ => "legacy run-based benchmark invocation",
    /\bmatrix --bench\b/ => "legacy matrix-based benchmark invocation",
    /\.liquid extension is optional/i => "extensionless filesystem guidance",
  }.freeze

  def test_every_readme_and_agents_file_uses_current_cli_names
    assert_equal [".beads/README.md", "AGENTS.md", "README.md"], relative_documentation_files

    DOCUMENTATION_FILES.each do |path|
      content = File.read(path)
      STALE_PATTERNS.each do |pattern, description|
        refute_match pattern, content, "#{relative(path)} contains #{description}"
      end
    end
  end

  def test_agents_verifier_categories_match_script_headers
    agents = File.read(File.join(ROOT, "AGENTS.md"))
    blocking_section = agents[/\*\*Blocking verifiers\*\*.*?(?=\*\*Advisory verifiers\*\*)/m]
    advisory_section = agents[/\*\*Advisory verifiers\*\*.*?(?=Error-mode policy)/m]

    Liquid::Spec::Verifiers::VERIFIER_MODULES.each_key do |name|
      script = File.join(Liquid::Spec::Verifiers.default_verifiers_dir, "#{name}.rb")
      expected_section = File.read(script, 500).include?("advisory: true") ? advisory_section : blocking_section
      assert_includes expected_section, "`#{name}`",
        "AGENTS.md puts #{name} in the wrong verifier category"
    end
  end

  def test_agents_suite_defaults_match_suite_configuration
    agents = File.read(File.join(ROOT, "AGENTS.md"))

    Liquid::Spec::Suite.all.each do |suite|
      expected = "**`#{suite.id}`** (default: #{suite.default?})"
      assert_includes agents, expected, "AGENTS.md has stale defaults for #{suite.id}"
    end
  end

  def test_readme_suite_counts_match_loaded_suites
    readme = File.read(File.join(ROOT, "README.md"))
    documented_counts = readme.scan(/^\| \*\*(\w+)\*\* \| ([\d,]+) \|/).to_h do |name, count|
      [name.to_sym, count.delete(",").to_i]
    end

    Liquid::Spec::Suite.all.each do |suite|
      actual = Liquid::Spec::SpecLoader.load_suite(suite).size
      assert_equal actual, documented_counts[suite.id],
        "README suite count for #{suite.id} is missing or stale"
    end
  end

  def test_readme_lists_the_current_benchmark_specs
    readme = File.read(File.join(ROOT, "README.md"))
    suite = Liquid::Spec::Suite.find(:benchmarks)

    specs = Liquid::Spec::SpecLoader.load_suite(suite)
    assert_includes readme, "includes #{specs.size} realistic templates"

    specs.each do |spec|
      assert_includes readme, "`#{spec.name}`",
        "README benchmark inventory is missing #{spec.name}"
    end
  end

  private

  def relative_documentation_files
    DOCUMENTATION_FILES.map { |path| relative(path) }
  end

  def relative(path)
    path.delete_prefix("#{ROOT}/")
  end
end
