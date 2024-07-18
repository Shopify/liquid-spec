# frozen_string_literal: true

require "timecop"
require_relative "failure_message"

module Liquid
  module Spec
    class Assertions < Module
      TEST_TIME = Time.utc(2024, 0o1, 0o1, 0, 1, 58).freeze

      def self.render_in_forked_process(adapter, spec)
        read, write = IO.pipe
        pid = fork do
          read.close

          begin
            rendered, _context = adapter.render(spec)
            write.write(Marshal.dump(rendered))
          rescue Exception => e # rubocop:disable Lint/RescueException
            begin
              write.write(Marshal.dump(e))
            rescue Timeout::ExitException => e
              write.write(Marshal.dump(e))
            end
          end
          write.close
          exit!
        end
        write.close
        rendered = begin
          Marshal.load(read.read)
        rescue => e
          RuntimeError.new("failed to load rendered result from forked process (#{e.class})")
        end
        Process.wait(pid)

        if rendered.is_a?(Exception)
          e = rendered.is_a?(Liquid::InternalError) ? rendered.cause : rendered
          e.message << "\n(❌ error when rendering with #{adapter.class.name})"
          raise e
        end

        rendered
      end

      def self.new(assert_method_name:, expected_adapter_proc:, actual_adapter_proc:)
        Module.new do |mod|
          mod.define_method("#{assert_method_name}_for_spec") do |spec, verify: true, run_command: "dev test"|
            opts = spec.to_h
            expected = opts.delete(:expected)
            liquid_code = opts.delete(:template)

            send(assert_method_name, liquid_code, verify: verify, expected: expected, run_command: run_command, **opts)
          end

          mod.define_method(assert_method_name) do |liquid_code, expected: nil, verify: true, run_command: "dev test", name: nil, **spec_opts|
            name = name || caller_locations.find { |l| l.label.start_with?("test_") }&.label || caller_locations.first.label
            expected_adapter = expected_adapter_proc.call
            actual_adapter = actual_adapter_proc.call

            Timecop.freeze(TEST_TIME) do
              expected_spec = Unit.new(
                name: name,
                template: liquid_code,
                expected: expected,
                exception_renderer: StubExceptionRenderer.new(raise_internal_errors: false),
                **spec_opts,
              )

              expected_render_result = verify ? Assertions.render_in_forked_process(expected_adapter, expected_spec) : expected

              if verify && expected && (expected_render_result != expected)
                exception = begin
                  pastel = Pastel.new
                  spec = expected_spec.dup
                  template_opts = { line_numbers: true, error_mode: spec.error_mode&.to_sym }
                  template_opts = template_opts.compact!.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
                  context_static_environments = spec.context&.static_environments || Marshal.load(Marshal.dump(spec.environment))
                  adapter_slug = expected_adapter.class.name.split("::").last.downcase
                  optional_template_name = spec.template_name ? "\n  > #{pastel.bold.green("template.name")} = #{spec.template_name.inspect}" : ""
                  context_static_environments = "YAML.unsafe_load(#{context_static_environments.to_yaml.dump})"

                  info = <<~INFO
                    When using `assert_liquid_ruby_parity`, make sure the `expected:` argument is correct.

                    #{SuperDiff::EqualityMatchers::Main.call(expected:, actual: expected_render_result)}

                    To reproduce the mismatch, you can copy and paste the following code into dev console:

                      $ dev console

                      > #{pastel.bold.green("template")} = Liquid::Template.parse(#{liquid_code.inspect}, #{template_opts})#{optional_template_name}
                      > #{pastel.bold.green("ctx")} = #{spec.context_klass}.build(static_environments: #{context_static_environments})
                      > #{pastel.bold.green("#{adapter_slug}_result")} = template.render(ctx)
                  INFO

                  FileUtils.mkdir_p("tmp/liquid-spec")
                  File.binwrite("tmp/liquid-spec/repro-help.txt", info)

                  raise "Expected result does not match rendered result (adapter: #{expected_adapter.class.name})\n\n#{info}"
                rescue => e
                  e
                end

                message = FailureMessage.new(
                  expected_spec,
                  expected_render_result,
                  exception: exception,
                  run_command: run_command,
                  test_name: name,
                  context: expected_adapter.build_liquid_context(expected_spec).tap do |context|
                    context.exception_renderer = expected_spec.exception_renderer
                  end,
                )
                assert(expected_render_result == expected, message)
              end

              spec = expected_spec.dup
              spec.expected = expected_render_result

              actual_rendered, actual_context, actual_exception = begin
                [*actual_adapter.render(spec), nil]
              rescue => e
                [nil, nil, e]
              end

              message = FailureMessage.new(
                spec,
                actual_rendered,
                exception: actual_exception,
                run_command: run_command,
                test_name: name,
                context: actual_context,
              )

              assert(expected_render_result == actual_rendered, message)
            rescue Minitest::Assertion => e
              e.set_backtrace([]) if actual_exception
              raise
            end
          end
        end
      end
    end
  end
end
