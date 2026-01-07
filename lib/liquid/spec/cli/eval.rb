# frozen_string_literal: true

require_relative "adapter_dsl"
require_relative "../spec_loader"

module Liquid
  module Spec
    module CLI
      # Eval command - quick test of a template against an adapter
      module Eval
        HELP = <<~HELP
          Usage: liquid-spec eval ADAPTER <<EOF
                 name: upcase-test
                 complexity: 20
                 template: "{{ x | upcase }}"
                 expected: "HI"
                 environment:
                   x: hi
                 hint: "Test upcase filter on simple string variable"
                 EOF

                 liquid-spec eval ADAPTER --spec=FILE.yml [options]

          Quickly test a Liquid template against your adapter.

          Options:
            -s, --spec FILE.yml     Load test from a YAML spec file (or use stdin)
            -c, --compare [MODE]    Compare against reference (default: strict, or 'lax')
            -v, --verbose           Show detailed output
            -h, --help              Show this help

          Examples:
            liquid-spec eval examples/liquid_ruby.rb <<EOF
            name: upcase-test
            complexity: 20
            template: "{{ x | upcase }}"
            expected: "HI"
            environment:
              x: hi
            hint: "Test upcase filter on simple string variable"
            EOF

            liquid-spec eval my_adapter.rb --spec=my_test.yml
            liquid-spec eval my_adapter.rb --compare < my_test.yml

          When using --compare, 'expected' and 'errors' can be omitted - they will
          be filled in from the reference implementation output.

        HELP

        class << self
          def run(args)
            if args.empty? || args.include?("-h") || args.include?("--help")
              puts HELP
              return
            end

            adapter_file = args.shift
            options = parse_options(args)

            # Check for stdin input (heredoc or pipe)
            unless options[:spec_file]
              if !$stdin.tty?
                options[:stdin_yaml] = $stdin.read
              else
                $stderr.puts "Error: --spec FILE is required (or pipe YAML via stdin)"
                $stderr.puts "Run 'liquid-spec eval --help' for usage"
                exit(1)
              end
            end

            unless File.exist?(adapter_file)
              $stderr.puts "Error: Adapter file not found: #{adapter_file}"
              exit(1)
            end

            # Default to compare mode (strict)
            options[:compare] = :strict unless options.key?(:compare)

            run_eval(options, adapter_file)
          end

          def parse_options(args)
            options = {}

            while args.any?
              arg = args.shift
              case arg
              when "-s", "--spec"
                options[:spec_file] = args.shift
              when /\A--spec=(.+)\z/
                options[:spec_file] = ::Regexp.last_match(1)
              when "-c", "--compare"
                if args.first && !args.first.start_with?("-")
                  mode = args.shift.downcase
                  options[:compare] = mode == "lax" ? :lax : :strict
                else
                  options[:compare] = :strict
                end
              when /\A--compare=(.+)\z/
                mode = ::Regexp.last_match(1).downcase
                options[:compare] = mode == "lax" ? :lax : :strict
              when "-v", "--verbose"
                options[:verbose] = true
              end
            end

            options
          end

          def run_eval(options, adapter_file)
            # Load from spec file, stdin, or passed spec_data
            spec_data = nil
            if options[:spec_data]
              spec_data = options[:spec_data]
            elsif options[:spec_file]
              spec_data = load_spec_file(options)
            elsif options[:stdin_yaml]
              spec_data = load_spec_from_string(options[:stdin_yaml], options)
            end

            unless spec_data
              $stderr.puts "Error: No spec data provided"
              exit(1)
            end

            template_source = spec_data["template"]
            assigns = spec_data["environment"] || spec_data["assigns"] || {}
            expected = spec_data["expected"]
            verbose = options[:verbose]
            compare_mode = options[:compare]

            hint = spec_data["hint"]
            complexity = spec_data["complexity"]
            name = spec_data["name"]

            # Require name
            unless name
              $stderr.puts "\e[31mError: Name is required. Use -n NAME or add 'name:' to your spec.\e[0m"
              exit(1)
            end

            # Print spec header
            puts ""
            print_spec_header(template_source, name, hint, complexity, assigns, verbose)

            # Info messages for missing metadata
            if spec_data
              infos = []
              infos << "No 'complexity' set. Add: complexity: <number> (see COMPLEXITY.md)" unless complexity
              infos << "Add a 'hint' field to explain what this spec tests" unless hint
              infos.each { |msg| $stderr.puts "\e[36mInfo: #{msg}\e[0m" }
              puts "" unless infos.empty?
            end

            # If --compare mode, run reference implementation first
            reference_output = nil
            reference_error = nil
            if compare_mode
              reference_output, reference_error = run_reference_implementation(template_source, assigns, verbose, compare_mode)

              if reference_error
                spec_data ||= {}
                spec_data["errors"] ||= { "parse_error" => [reference_error.message] }
              elsif reference_output
                expected ||= reference_output
              end
            end

            # NOW load the user's adapter
            LiquidSpec.reset!
            LiquidSpec.running_from_cli!
            load(File.expand_path(adapter_file))
            LiquidSpec.run_setup!

            test_passed = true
            has_difference = false

            begin
              LiquidSpec.do_compile(template_source, { line_numbers: true })
              template = LiquidSpec.ctx[:template]

              if verbose && template.respond_to?(:source)
                puts "\e[2mGenerated code:\e[0m"
                puts template.source
                puts ""
              end

              render_options = { registers: {}, strict_errors: false }
              actual = LiquidSpec.do_render(assigns, render_options)

              if compare_mode && reference_error
                has_difference = true
              end

              if expected
                if actual == expected
                  print_pass(actual, compare_mode, reference_output)
                else
                  print_fail(expected, actual, hint, spec_data)
                  test_passed = false
                  has_difference = true
                end
              else
                print_output_only(actual)
              end

              if compare_mode && reference_error
                puts "\n\e[31mDifference: Reference raised error but your implementation succeeded\e[0m"
                puts "  Reference error: #{reference_error.class}: #{reference_error.message}"
                has_difference = true
              end

              final_spec = build_final_spec(
                name: name,
                hint: hint,
                complexity: complexity,
                template: template_source,
                assigns: assigns,
                expected: expected || actual,
                passed: test_passed,
              )

              append_to_daily_file(final_spec, has_difference)
              show_contribution_message(has_difference)

              exit(1) unless test_passed
            rescue SystemExit, Interrupt, SignalException
              raise
            rescue Exception => e
              print_error(e, hint, verbose, spec_data)

              if compare_mode
                if reference_error
                  if reference_error.class == e.class
                    puts "\e[32mBoth implementations raised same error type\e[0m"
                  else
                    puts "\e[31mDifference: Different error types\e[0m"
                    puts "  Reference: #{reference_error.class}"
                    puts "  Yours:     #{e.class}"
                    has_difference = true
                  end
                else
                  puts "\e[31mDifference: Reference succeeded but your implementation raised error\e[0m"
                  puts "  Reference output: #{reference_output.inspect}"
                  has_difference = true
                end
              end

              final_spec = build_final_spec(
                name: name,
                hint: hint,
                complexity: complexity,
                template: template_source,
                assigns: assigns,
                expected: expected,
                passed: false,
                error: e,
              )

              append_to_daily_file(final_spec, has_difference)
              show_contribution_message(has_difference)

              exit(1)
            end
          end

          # --- Output formatting ---

          def print_spec_header(template, name, hint, complexity, assigns, verbose)
            puts "\e[1m#{name}\e[0m"

            if hint
              puts "\e[36m#{hint.strip}\e[0m"
            end

            puts ""

            if template.include?("\n")
              puts "\e[2mTemplate:\e[0m"
              template.each_line { |line| puts "  #{line}" }
            else
              puts "\e[2mTemplate:\e[0m #{template}"
            end

            if verbose && assigns && !assigns.empty?
              puts "\e[2mEnvironment:\e[0m #{assigns.inspect}"
            end

            puts "\e[2mComplexity:\e[0m #{complexity}" if complexity

            puts ""
          end

          def print_pass(actual, compare_mode, reference_output)
            if compare_mode && reference_output == actual
              puts "\e[32m\u2713 PASS\e[0m (matches reference)"
            else
              puts "\e[32m\u2713 PASS\e[0m"
            end
            print_output_value(actual)
          end

          def print_fail(expected, actual, _hint, _spec_data)
            puts "\e[31m\u2717 FAIL\e[0m"
            puts ""

            puts "\e[2mExpected:\e[0m"
            print_indented(expected)
            puts ""
            puts "\e[2mActual:\e[0m"
            print_indented(actual)

            if expected.is_a?(String) && actual.is_a?(String) && expected.length < 200 && actual.length < 200
              diff = string_diff(expected, actual)
              puts "\n\e[2mDiff:\e[0m #{diff}" if diff
            end
          end

          def print_output_only(actual)
            puts "\e[36mOutput:\e[0m"
            print_indented(actual)
          end

          def print_error(error, _hint, verbose, _spec_data)
            puts "\e[31m\u2717 ERROR\e[0m #{error.class}"
            puts "  #{error.message}"

            if verbose
              puts ""
              puts "\e[2mBacktrace:\e[0m"
              error.backtrace.first(10).each { |line| puts "  #{line}" }
            end

            puts ""
          end

          def print_output_value(value)
            if value.to_s.empty?
              puts "  \e[2m(empty string)\e[0m"
            elsif value.include?("\n")
              print_indented(value)
            else
              puts "  #{value.inspect}"
            end
          end

          def print_indented(text)
            if text.to_s.empty?
              puts "  \e[2m(empty string)\e[0m"
            elsif text.include?("\n")
              text.each_line { |line| puts "  #{line.inspect.gsub(/\A"|"\z/, "")}" }
            else
              puts "  #{text.inspect}"
            end
          end

          def string_diff(expected, actual)
            min_len = [expected.length, actual.length].min
            first_diff = (0...min_len).find { |i| expected[i] != actual[i] } || min_len

            return if first_diff == 0 && expected.length == actual.length

            if expected.length != actual.length
              "at position #{first_diff}: length #{expected.length} vs #{actual.length}"
            else
              exp_char = expected[first_diff]&.inspect || "end"
              act_char = actual[first_diff]&.inspect || "end"
              "at position #{first_diff}: expected #{exp_char}, got #{act_char}"
            end
          end

          # --- Reference implementation ---

          REFERENCE_ADAPTERS = {
            strict: File.expand_path("../../../../examples/liquid_ruby.rb", __dir__),
            lax: File.expand_path("../../../../examples/liquid_ruby_lax.rb", __dir__),
          }.freeze

          def run_reference_implementation(template_source, assigns, _verbose, mode = :strict)
            adapter_file = REFERENCE_ADAPTERS[mode]
            puts "\e[2mComparing against reference (#{File.basename(adapter_file)})...\e[0m"

            # Fork a clean process to run the reference adapter
            reader, writer = IO.pipe

            pid = fork do
              reader.close

              begin
                LiquidSpec.reset!
                LiquidSpec.running_from_cli!
                load(adapter_file)
                LiquidSpec.run_setup!

                LiquidSpec.do_compile(template_source, { line_numbers: true })
                render_options = { registers: {}, strict_errors: false }
                output = LiquidSpec.do_render(assigns, render_options)

                Marshal.dump({ output: output, error: nil }, writer)
              rescue SystemExit, Interrupt, SignalException
                raise
              rescue Exception => e
                Marshal.dump({ output: nil, error: { class: e.class.name, message: e.message } }, writer)
              ensure
                writer.close
              end
            end

            writer.close
            result = Marshal.load(reader)
            reader.close
            Process.wait(pid)

            if result[:error]
              error = StandardError.new(result[:error][:message])
              error.define_singleton_method(:class_name) { result[:error][:class] }
              [nil, error]
            else
              [result[:output], nil]
            end
          rescue SystemExit, Interrupt, SignalException
            raise
          rescue Exception => e
            [nil, e]
          end

          # --- Spec loading ---

          def load_spec_file(options)
            require "yaml"

            spec_file = options[:spec_file]
            unless File.exist?(spec_file)
              $stderr.puts "Error: Spec file not found: #{spec_file}"
              exit(1)
            end

            load_spec_from_string(File.read(spec_file), options)
          end

          def load_spec_from_string(yaml_content, options)
            spec = Liquid::Spec.safe_yaml_load(yaml_content)

            unless spec.is_a?(Hash)
              $stderr.puts "Error: Invalid spec format - expected YAML hash with 'template' key"
              exit(1)
            end

            options[:liquid] = spec["template"] || spec[:template]
            options[:expected] = spec["expected"] || spec[:expected] if spec.key?("expected") || spec.key?(:expected)
            options[:assigns] = spec["environment"] || spec[:environment] || spec["assigns"] || spec[:assigns] || {}

            unless options[:liquid]
              $stderr.puts "Error: Spec must contain 'template' key"
              exit(1)
            end

            spec
          end

          def build_final_spec(name:, hint:, complexity:, template:, assigns:, expected:, passed:, error: nil)
            spec = {}
            spec["name"] = name
            spec["hint"] = hint if hint
            spec["complexity"] = complexity if complexity
            spec["template"] = template
            spec["expected"] = expected if expected && !error
            spec["environment"] = assigns if assigns && !assigns.empty?

            if error
              # Check if error class name contains "SyntaxError"
              error_type = error.class.name.include?("SyntaxError") ? "parse_error" : "render_error"
              spec["errors"] = { error_type => parse_error_patterns(error.message) }
            end

            spec["_passed"] = passed
            spec
          end

          def parse_error_patterns(message)
            if message =~ /\A([^\(]+)\s*\(line\s+(\d+)\):\s*(.+)\z/
              error_type = ::Regexp.last_match(1).strip
              line_num = ::Regexp.last_match(2).strip
              details = ::Regexp.last_match(3).strip
              [error_type, line_num, details]
            else
              [message.strip]
            end
          end

          # --- File output ---

          def append_to_daily_file(spec_data, _has_difference)
            require "yaml"
            require "date"

            daily_file = "/tmp/liquid-spec-#{Date.today}.yml"

            output_spec = spec_data.dup
            output_spec.delete(:stdin_yaml)
            output_spec.delete("stdin_yaml")

            ordered_spec = {}
            ["name", "hint", "complexity", "template", "expected", "environment", "errors", "_passed"].each do |key|
              ordered_spec[key] = output_spec[key] if output_spec.key?(key)
            end
            output_spec.each { |k, v| ordered_spec[k] = v unless ordered_spec.key?(k) }
            ordered_spec.compact!

            existing_specs = []
            if File.exist?(daily_file) && File.size?(daily_file).to_i > 0
              existing_specs = Liquid::Spec.safe_yaml_load(File.read(daily_file)) || []
              existing_specs = [] unless existing_specs.is_a?(Array)
            end

            existing_specs << ordered_spec
            File.write(daily_file, existing_specs.to_yaml)

            puts ""
            puts "\e[2mSaved to: #{daily_file}\e[0m"
          end

          def show_contribution_message(has_difference)
            return unless has_difference

            puts ""
            puts "\e[1;33m#{"=" * 60}\e[0m"
            puts "\e[1;33m  DIFFERENCE DETECTED\e[0m"
            puts "\e[1;33m#{"=" * 60}\e[0m"
            puts ""
            puts "This spec reveals a behavioral difference worth documenting."
            puts "\e[1mPlease contribute it:\e[0m \e[4mhttps://github.com/Shopify/liquid-spec\e[0m"
            puts ""
          end
        end
      end
    end
  end
end
