# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "liquid/spec/adversarial"
require "liquid/spec/cli/adversarial"

class AdversarialTest < Minitest::Test
  Adversarial = Liquid::Spec::Adversarial

  class FakeRunner
    attr_reader :ctx

    def initialize(&render)
      @render = render
      @ctx = {}
    end

    def ensure_setup!
      self
    end

    def run(specs)
      result = Liquid::Spec::RunResult.new(adapter: self, specs: specs)
      specs.each do |spec|
        entry = case (value = @render.call(spec))
        when Exception
          Liquid::Spec::SpecResult.new(
            spec: spec,
            status: :error,
            output: "#{value.class}: #{value.message}"
          )
        when :skip
          Liquid::Spec::SpecResult.new(spec: spec, status: :skipped, reason: "unsupported")
        else
          Liquid::Spec::SpecResult.new(spec: spec, status: :pass, output: value.to_s)
        end
        result.add(entry)
        yield entry if block_given?
      end
      result
    end
  end

  def test_mutators_cover_whitespace_values_lookups_filters_control_flow_and_structure
    samples = {
      Adversarial::Mutators::DelimiterWhitespace.new => "Hello {{ user.name | upcase }}",
      Adversarial::Mutators::TrimMarkers.new => "A {{ x }} B",
      Adversarial::Mutators::Literals.new => "{{ 'hello' | plus: 2 }}",
      Adversarial::Mutators::Lookups.new => "{{ user.name }}",
      Adversarial::Mutators::Filters.new => "{{ name | upcase }}",
      Adversarial::Mutators::Conditionals.new => "{% if x == 1 %}yes{% endif %}",
      Adversarial::Mutators::Loops.new => "{% for x in xs %}{{ x }}{% endfor %}",
      Adversarial::Mutators::TagStructure.new => "{% if x %}yes{% endif %}",
      Adversarial::Mutators::OpaqueBodies.new => "{% raw %}hello{% endraw %}",
    }

    samples.each do |mutator, template|
      variants = mutator.variants(template)
      refute_empty variants, "#{mutator.class} generated no variants"
      assert variants.all? { |variant| variant.template != template }
      assert variants.all? { |variant| variant.id.start_with?(mutator.id) }
    end
  end

  def test_fuzz_generation_is_reproducible_by_seed
    seeds = [seed_spec("one", "{{ user.name | upcase }}"), seed_spec("two", "{% if x %}x{% endif %}")]

    first = Adversarial::Generator.new(seed: 123).generate(seeds, mode: :fuzz, limit: 10, rounds: 50)
    second = Adversarial::Generator.new(seed: 123).generate(seeds, mode: :fuzz, limit: 10, rounds: 50)

    assert_equal first.map { |entry| [entry.id, entry.spec.template] },
      second.map { |entry| [entry.id, entry.spec.template] }
  end

  def test_seed_loader_reproduces_generated_spec_inputs
    first = Adversarial::SeedLoader.new(
      around: "drop_method_square_random",
      seed: 77
    ).load
    second = Adversarial::SeedLoader.new(
      around: "drop_method_square_random",
      seed: 77
    ).load

    assert_equal first.map(&:template), second.map(&:template)
    assert_equal first.map(&:expected), second.map(&:expected)
  end

  def test_stress_generation_is_bounded_and_validly_nested
    mutator = Adversarial::Mutators::StructuralStress.new(depth: 3, repetitions: 4)
    generator = Adversarial::Generator.new(mutators: [mutator], seed: 1)

    cases = generator.generate([seed_spec("text", "hello")], mode: :stress, limit: 2)

    assert_equal 2, cases.length
    assert_includes cases.first.spec.template, "{% if true %}{% if true %}{% if true %}"
    assert_equal "hello" * 4, cases.last.spec.template
  end

  def test_comparator_classifies_output_and_error_differences
    comparator = Adversarial::Comparator.new
    ok = ->(output) { Adversarial::Outcome.new(status: :ok, output: output) }
    error = ->(category) { Adversarial::Outcome.new(status: :error, error_category: category) }

    assert_nil comparator.compare(ok.call("same"), ok.call("same"))
    assert_equal :output_mismatch, comparator.compare(ok.call("a"), ok.call("b"))
    assert_nil comparator.compare(error.call(:syntax), error.call(:syntax))
    assert_equal :error_category_mismatch, comparator.compare(error.call(:syntax), error.call(:render))
    assert_equal :reference_error_subject_ok, comparator.compare(error.call(:syntax), ok.call(""))
  end

  def test_minimizer_reduces_while_preserving_predicate
    minimized = Adversarial::Minimizer.new(budget: 100).minimize("prefix BUG suffix") do |candidate|
      candidate.include?("BUG")
    end

    assert_includes minimized, "BUG"
    assert_operator minimized.length, :<, "prefix BUG suffix".length
  end

  def test_engine_detects_and_saves_differential_regression
    reference = FakeRunner.new { |spec| "reference:#{spec.template}" }
    subject = FakeRunner.new { |spec| "subject:#{spec.template}" }

    Dir.mktmpdir do |dir|
      summary = Adversarial::Engine.new(
        adapter: "unused",
        mode: :mutate,
        around: "object_string_literal",
        limit: 1,
        save_dir: dir,
        minimize: true,
        minimize_budget: 5,
        subject_runner: subject,
        reference_runner: reference,
      ).run

      assert_equal 1, summary.generated
      assert_equal 1, summary.findings.length
      finding = summary.findings.first
      assert_equal :output_mismatch, finding.classification
      assert_equal "reference:#{finding.case.spec.template}", finding.reference.output
      assert File.exist?(finding.saved_to)

      data = Liquid::Spec.safe_yaml_load(File.read(finding.saved_to))
      saved = data.fetch("specs").first
      assert_equal finding.reference.output, saved.fetch("expected")
      assert_includes saved.fetch("hint"), "Mutations:"
    end
  end

  def test_engine_treats_matching_generated_outputs_as_success
    runner = FakeRunner.new { |spec| spec.template }
    summary = Adversarial::Engine.new(
      adapter: "unused",
      mode: :mutate,
      around: "object_string_literal",
      limit: 2,
      save_dir: nil,
      subject_runner: runner,
      reference_runner: runner,
    ).run

    assert summary.success?
    assert_equal 2, summary.passed
  end

  def test_cli_parses_reproduction_and_generation_options
    options = Liquid::Spec::CLI::Adversarial.parse_options(
      %w[
        --around=for_loops --seed=42 --limit=9 --rounds=30
        --features=drops,strict2_parsing --timeout=4.5 --minimize
        --minimize-budget=12 --depth=20 --repetitions=25 --no-save --json
      ],
      :fuzz
    )

    assert_equal "for_loops", options[:around]
    assert_equal 42, options[:seed]
    assert_equal 9, options[:limit]
    assert_equal 30, options[:rounds]
    assert_equal [:drops, :strict2_parsing], options[:features]
    assert_equal 4.5, options[:timeout]
    assert options[:minimize]
    assert_equal 12, options[:minimize_budget]
    assert_equal 20, options[:depth]
    assert_equal 25, options[:repetitions]
    assert_nil options[:save_dir]
    assert options[:json]
  end

  private

  def seed_spec(name, template)
    Liquid::Spec::LazySpec.new(
      name: name,
      template: template,
      expected: "",
      complexity: 10,
      raw_environment: {},
      raw_filesystem: {},
    )
  end
end
