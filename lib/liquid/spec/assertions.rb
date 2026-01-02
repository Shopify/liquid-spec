# frozen_string_literal: true

require "timecop"
require_relative "failure_message"
require_relative "adapter/default"

module Liquid
  module Spec
    class Assertions < Module
      TEST_TIME = Time.utc(2024, 0o1, 0o1, 0, 1, 58).freeze

      # Deep duplicate an object, handling special cases
      def self.deep_dup(obj)
        case obj
        when Hash
          obj.transform_keys { |k| deep_dup(k) }.transform_values { |v| deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        when String
          obj.dup
        when Numeric, Symbol, TrueClass, FalseClass, NilClass
          obj
        when Class
          obj # Don't dup classes
        when Proc
          obj # Procs can't be duped
        else
          # Try dup, fall back to the object itself
          begin
            obj.dup
          rescue TypeError
            obj
          end
        end
      end

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
          e.message << "\n(error when rendering with #{adapter.class.name})"
          raise e
        end

        rendered
      end

      def self.new(assert_method_name: :assert_parity, expected_adapter_proc: -> { Adapter::Default.new }, actual_adapter_proc:)
        Module.new do |mod|
          mod.define_method("#{assert_method_name}_for_spec") do |spec, run_command: "dev test"|
            opts = spec.to_h
            expected = opts.delete(:expected)
            liquid_code = opts.delete(:template)

            send(assert_method_name, liquid_code, expected: expected, run_command: run_command, **opts)
          end

          mod.define_method(assert_method_name) do |liquid_code, expected: nil, run_command: "dev test", name: nil, **spec_opts|
            name = name || caller_locations.find { |l| l.label.start_with?("test_") }&.label || caller_locations.first.label
            expected_adapter = expected_adapter_proc.call
            actual_adapter = actual_adapter_proc.call
            spec_opts[:exception_renderer] ||= StubExceptionRenderer.new(raise_internal_errors: false)
            spec_opts[:name] = name
            spec_opts[:template] = liquid_code
            spec_opts[:expected] = expected

            Timecop.freeze(TEST_TIME) do
              # Use deep_dup instead of Marshal.dump/load to avoid class serialization issues
              expected_spec = Unit.new(**Assertions.deep_dup(spec_opts))

              expected_render_result, expected_context, expected_err = begin
                expected_adapter.render(expected_spec)
              rescue => e
                [nil, nil, e]
              end

              if expected
                message = FailureMessage.new(
                  expected_spec,
                  expected_render_result,
                  message: "the expected parameter given doesn't match the output of the " \
                    "#{expected_adapter.class.name} adapter, please check the expected parameter",
                  exception: expected_err,
                  run_command: run_command,
                  test_name: name,
                  context: expected_context,
                )

                assert(expected == expected_render_result, message)
              end

              actual_opts = Assertions.deep_dup(spec_opts)
              actual_opts[:expected] = expected_render_result
              actual_spec = Unit.new(**actual_opts)

              actual_rendered, actual_context, actual_exception = begin
                [*actual_adapter.render(actual_spec), nil]
              rescue => e
                [nil, nil, e]
              end

              message = FailureMessage.new(
                actual_spec,
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
