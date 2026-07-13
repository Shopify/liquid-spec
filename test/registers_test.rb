# frozen_string_literal: true

require_relative "test_helper"
require "liquid/spec/adapter_runner"

class RegistersTest < Minitest::Test
  include Liquid::Spec::TestHelpers

  module CurrentTimeFilter
    def current_time_from_register(_input)
      @context.registers[:current_time].iso8601
    end
  end

  def test_current_time_is_a_render_register_not_an_assign
    runner = Liquid::Spec::AdapterRunner.new(name: "register_probe")
    runner.on_compile { |_ctx, _source, _options| }
    observed = nil
    runner.on_render do |_ctx, assigns, options|
      observed = [assigns, options.fetch(:registers)]
      "ok"
    end

    spec = create_spec(expected: "ok")
    frozen = Time.utc(2031, 7, 19, 14, 15, 16)
    result = Liquid::Spec::TimeFreezer.freeze(frozen) { runner.run_single(spec) }

    assert result.passed?
    assigns, registers = observed
    refute assigns.key?(:current_time)
    assert_equal frozen, registers[:current_time]
  end

  def test_real_liquid_context_hides_registers_from_templates_but_exposes_them_to_filters
    require "liquid"
    time = Time.utc(2031, 7, 19, 14, 15, 16)
    template = Liquid::Template.parse("{{ current_time }}|{{ '' | current_time_from_register }}")
    context = Liquid::Context.build(registers: Liquid::Registers.new(current_time: time))
    context.add_filters(CurrentTimeFilter)

    assert_equal "|2031-07-19T14:15:16Z", template.render(context)
  end

  def test_adapter_suite_selection_skips_specs_outside_its_configured_suites
    runner = Liquid::Spec::AdapterRunner.new(name: "bench_only")
    runner.instance_variable_set(:@suites, [:benchmarks])

    benchmark = create_spec(source_file: "/tmp/specs/benchmarks/specs.yml")
    core = create_spec(source_file: "/tmp/specs/liquid_ruby/specs.yml")

    assert runner.can_run?(benchmark)
    refute runner.can_run?(core)
  end
end
