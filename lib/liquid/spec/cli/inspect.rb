# frozen_string_literal: true

require_relative "adapter_dsl"
require_relative "../time_freezer"
require "yaml"

module Liquid
  module Spec
    module CLI
      # Inspect command - shows detailed info about a specific test
      module Inspect
        TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze

        HELP = <<~HELP
          Usage: liquid-spec inspect ADAPTER -n PATTERN [options]

          Shows detailed information about matching specs including:
          - Full template source
          - Environment/assigns
          - Expected output
          - Your adapter's actual output
          - Difference if any

          Options:
            -n, --name PATTERN      Spec name pattern (required)
            -s, --suite SUITE       Spec suite: all, liquid_ruby, basics, etc.
            --strict                Only inspect specs with error_mode: strict
            --print-actual          Output YAML spec matching actual behavior (for updating specs)
            --print-il              Print intermediate representation (IL/bytecode) if available
            --print-ruby            Print generated Ruby source code if available
            --render-errors=BOOL    Force render_errors setting (true/false) for --print-actual
            -h, --help              Show this help

          Examples:
            liquid-spec inspect my_adapter.rb -n "case.*empty"
            liquid-spec inspect my_adapter.rb -n "for loop first"
            liquid-spec inspect my_adapter.rb -n "include tag" --print-actual
            liquid-spec inspect my_adapter.rb -n "some error" --print-actual --render-errors=false

          The --print-actual flag outputs a YAML spec that matches the actual behavior,
          using best practices like error substring matching for error specs.

        HELP

        class << self
          def run(args)
            if args.empty? || args.include?("-h") || args.include?("--help")
              puts HELP
              return
            end

            adapter_file = args.shift
            options = parse_options(args)

            unless options[:filter]
              $stderr.puts "Error: -n PATTERN is required for inspect"
              $stderr.puts "Run 'liquid-spec inspect --help' for usage"
              exit(1)
            end

            unless File.exist?(adapter_file)
              $stderr.puts "Error: Adapter file not found: #{adapter_file}"
              exit(1)
            end

            # Load the adapter
            LiquidSpec.reset!
            LiquidSpec.running_from_cli!
            load(File.expand_path(adapter_file))

            config = LiquidSpec.config || LiquidSpec.configure
            config.suite = options[:suite] if options[:suite]
            config.filter = options[:filter]
            config.strict_only = options[:strict_only] if options[:strict_only]

            inspect_specs(config, options)
          end

          def parse_options(args)
            options = {}

            while args.any?
              arg = args.shift
              case arg
              when "-n", "--name"
                pattern = args.shift
                options[:filter] = Regexp.new(pattern, Regexp::IGNORECASE)
              when /\A--name=(.+)\z/, /\A-n(.+)\z/
                options[:filter] = Regexp.new(::Regexp.last_match(1), Regexp::IGNORECASE)
              when "-s", "--suite"
                options[:suite] = args.shift.to_sym
              when /\A--suite=(.+)\z/
                options[:suite] = ::Regexp.last_match(1).to_sym
              when "--strict"
                options[:strict_only] = true
              when "--print-actual"
                options[:print_actual] = true
              when "--print-il"
                options[:print_il] = true
              when "--print-ruby"
                options[:print_ruby] = true
              when /\A--render-errors=(.+)\z/
                options[:force_render_errors] = ::Regexp.last_match(1).downcase == "true"
              end
            end

            options
          end

          def inspect_specs(config, options)
            # Run setup first
            LiquidSpec.run_setup!

            # Load spec components
            require "liquid/spec"
            require "liquid/spec/deps/liquid_ruby"

            specs = load_specs(config)
            specs = specs.select { |s| s.name =~ config.filter }
            specs = filter_strict_only(specs) if config.strict_only

            if specs.empty?
              puts "No specs matching pattern: #{config.filter.inspect}"
              return
            end

            if options[:print_actual]
              print_actual_specs(specs, config, options)
            else
              puts "Found #{specs.size} matching spec(s)"
              puts "=" * 80

              specs.each_with_index do |spec, idx|
                puts "" if idx > 0
                inspect_single_spec(spec, config, options)
                puts "=" * 80
              end
            end
          end

          def inspect_single_spec(spec, config, options = {})
            # Show source location
            puts "\e[2m#{spec.source_file}#{spec.line_number ? ":#{spec.line_number}" : ""}\e[0m"
            puts "\e[1m#{spec.name}\e[0m"

            # Show hint if present
            hint = spec.effective_hint
            if hint && !hint.empty?
              puts "\e[36m#{hint.strip}\e[0m"
            end

            # Show complexity and render_errors
            metadata = []
            metadata << "complexity: #{spec.complexity}" if spec.complexity
            metadata << "render_errors: #{spec.render_errors}" if spec.render_errors
            metadata << "error_mode: #{spec.error_mode}" if spec.error_mode
            puts "\e[2m#{metadata.join(", ")}\e[0m" unless metadata.empty?

            puts ""
            puts "-" * 80

            puts "\n\e[2mTemplate:\e[0m"
            if spec.template.include?("\n")
              spec.template.each_line { |line| puts "  #{line}" }
            else
              puts "  #{spec.template}"
            end

            environment = spec.instantiate_environment
            if environment && !environment.empty?
              puts "\n\e[2mEnvironment:\e[0m"
              environment.each do |key, value|
                puts "  #{key}: #{value.inspect}"
              end
            end

            filesystem = spec.raw_filesystem
            if filesystem.is_a?(Hash) && !filesystem.empty?
              puts "\n\e[2mFilesystem:\e[0m"
              filesystem.each do |name, content|
                puts "  #{name}:"
                content.each_line { |l| puts "    #{l}" }
              end
            end

            puts "\n\e[2mExpected:\e[0m"
            print_value(spec.expected)

            puts "\n\e[2mActual:\e[0m"
            TimeFreezer.freeze(TEST_TIME) do
              result = run_with_adapter(spec, config, options)

              # Print IL/Ruby if requested and available
              if options[:print_il] || options[:print_ruby]
                print_generated_code(result[:template], options)
              end

              if result[:error]
                puts "  \e[31mERROR:\e[0m #{result[:error].class}: #{result[:error].message}"
                result[:error].backtrace.first(5).each { |line| puts "    #{line}" }
              else
                print_value(result[:actual])
              end

              puts ""
              if result[:error].nil? && result[:actual] == spec.expected
                puts "\e[32m\u2713 PASS\e[0m"
              elsif result[:error] && spec.errors.any?
                # Check if error matches expected patterns
                if error_matches_spec?(result[:error], spec)
                  puts "\e[32m\u2713 PASS\e[0m (error matches expected pattern)"
                else
                  puts "\e[31m\u2717 FAIL\e[0m (error doesn't match expected pattern)"
                  print_failure_hints(spec)
                end
              else
                puts "\e[31m\u2717 FAIL\e[0m"
                if result[:actual] && spec.expected
                  diff = string_diff(spec.expected, result[:actual])
                  puts "\n\e[2mDiff:\e[0m #{diff}" if diff
                end
                print_failure_hints(spec)
              end
            end
          end

          def print_failure_hints(spec)
            hint = spec.effective_hint
            if hint && !hint.empty?
              puts "\n\e[33mHint:\e[0m #{hint.strip.gsub("\n", "\n      ")}"
            end
            puts "\nRun with --print-actual to generate updated spec"
          end

          def print_actual_specs(specs, config, options)
            TimeFreezer.freeze(TEST_TIME) do
              specs.each_with_index do |spec, idx|
                puts "" if idx > 0
                result = run_with_adapter(spec, config, options)
                print_actual_spec_yaml(spec, result, options)
              end
            end
          end

          def print_actual_spec_yaml(spec, result, options = {})
            # Determine effective render_errors setting
            render_errors = if options.key?(:force_render_errors)
              options[:force_render_errors]
            else
              spec.render_errors
            end

            # Print spec as YAML with comments for errors
            puts "- name: #{yaml_value(spec.name)}"

            hint = spec.effective_hint
            if hint && !hint.empty?
              puts "  hint: |"
              hint.each_line { |line| puts "    #{line.rstrip}" }
            end

            puts "  complexity: #{spec.complexity}" if spec.complexity && spec.complexity < 1000

            puts "  template: #{yaml_value(spec.template)}"

            env = spec.raw_environment
            if env && !env.empty?
              puts "  environment:"
              env.each do |key, value|
                puts "    #{key}: #{yaml_value(value)}"
              end
            end

            fs = spec.raw_filesystem
            if fs && !fs.empty?
              puts "  filesystem:"
              fs.each do |name, content|
                if content.include?("\n")
                  puts "    #{name}: |"
                  content.each_line { |line| puts "      #{line.rstrip}" }
                else
                  puts "    #{name}: #{yaml_value(content)}"
                end
              end
            end

            if result[:error]
              # Exception was raised - use render_error or parse_error
              error = result[:error]
              error_info = parse_error_message(error)

              # render_errors: false means strict_errors: true, which throws
              # So if we got an exception, render_errors should be false (or omitted)
              puts "  # Actual error: #{error.class}: #{error.message}"
              puts "  errors:"
              puts "    #{error_info[:type]}:"

              error_info[:patterns].each do |pattern|
                puts "      - #{yaml_value(pattern)}"
              end
            elsif result[:actual] =~ /\ALiquid(?: \w+)? error/i
              # Output contains an error message - use errors.output
              # This happens when render_errors: true (strict_errors: false)
              error_info = parse_output_error(result[:actual])

              puts "  render_errors: true"
              puts "  # Actual output: #{result[:actual].inspect}"
              puts "  errors:"
              puts "    output:"

              error_info[:patterns].each do |pattern|
                puts "      - #{yaml_value(pattern)}"
              end
            else
              # Normal output
              puts "  expected: #{yaml_value(result[:actual])}"
              puts "  render_errors: true" if render_errors
            end

            puts "  error_mode: #{spec.error_mode}" if spec.error_mode
          end

          def yaml_value(value)
            case value
            when nil
              "null"
            when true, false
              value.to_s
            when Integer, Float
              value.to_s
            when String
              if value.include?("\n")
                "|\n" + value.each_line.map { |l| "    #{l.rstrip}" }.join("\n")
              elsif value.empty?
                '""'
              elsif value =~ /\A[\w\s.,!?-]+\z/ && !value.start_with?(" ") && !value.end_with?(" ")
                # Simple string without special chars
                value.inspect
              else
                value.inspect
              end
            else
              value.inspect
            end
          end

          def parse_error_message(error)
            message = error.message

            # Determine error type based on exception class name containing "SyntaxError"
            error_type = error.class.name.include?("SyntaxError") ? "parse_error" : "render_error"

            patterns = []

            # Parse structured error: "Liquid error (line N): message" or "Liquid error (file line N): message"
            if message =~ /\A(Liquid \w+ error|Liquid error)\s*\((?:(\S+)\s+)?line\s+(\d+)\):\s*(.+)\z/i
              error_kind = ::Regexp.last_match(1)
              # file_name = ::Regexp.last_match(2)  # Don't match on filename
              line_num = ::Regexp.last_match(3)
              details = ::Regexp.last_match(4).strip

              # Match error type (e.g., "Liquid syntax error")
              patterns << error_kind

              # Match line number (keep "line N" format)
              patterns << "line #{line_num}"

              # Match core error message (strip trailing context)
              core_message = details.sub(/\s+in\s+"[^"]*"\s*\z/i, "").strip
              patterns << core_message unless core_message.empty?
            else
              # Fallback: extract key parts
              # Remove variable line numbers for flexibility
              cleaned = message.sub(/\s+in\s+"[^"]*"\s*\z/i, "").strip
              patterns << cleaned unless cleaned.empty?
            end

            { type: error_type, patterns: patterns }
          end

          def parse_output_error(output)
            patterns = []

            # Parse error message from output
            # Format: "Liquid error (line N): message" or "Liquid error (file line N): message"
            if output =~ /\A(Liquid \w+ error|Liquid error)\s*\((?:(\S+)\s+)?line\s+(\d+)\):\s*(.+)\z/i
              error_kind = ::Regexp.last_match(1)
              line_num = ::Regexp.last_match(3)
              details = ::Regexp.last_match(4).strip

              patterns << error_kind
              patterns << "line #{line_num}"

              core_message = details.sub(/\s+in\s+"[^"]*"\s*\z/i, "").strip
              patterns << core_message unless core_message.empty?
            else
              # Fallback
              patterns << output.strip
            end

            { patterns: patterns }
          end

          def error_matches_spec?(error, spec)
            return false unless spec.errors.any?

            message = error.message.downcase

            spec.errors.any? do |_type, patterns|
              Array(patterns).all? do |pattern|
                if pattern.is_a?(Regexp)
                  pattern.match?(message)
                else
                  message.include?(pattern.to_s.downcase)
                end
              end
            end
          end

          def print_value(value)
            if value.nil?
              puts "  \e[2m(nil)\e[0m"
            elsif value.to_s.empty?
              puts "  \e[2m(empty string)\e[0m"
            elsif value.include?("\n")
              value.each_line.with_index do |line, i|
                puts "  #{i + 1}: #{line.chomp.inspect}"
              end
            else
              puts "  #{value.inspect}"
            end
          end

          def string_diff(expected, actual)
            return "expected output, got (empty string)" if actual.to_s.empty?
            return "expected (empty string), got output" if expected.to_s.empty?

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

          def run_with_adapter(spec, _config, options = {})
            required_opts = spec.source_required_options || {}

            # Use forced render_errors if provided, otherwise use spec's setting
            render_errors = if options.key?(:force_render_errors)
              options[:force_render_errors]
            else
              spec.render_errors || required_opts[:render_errors] || spec.expects_render_error?
            end

            # Build filesystem first so it can be passed to compile
            filesystem = spec.instantiate_filesystem

            compile_options = {
              line_numbers: true,
              error_mode: spec.error_mode&.to_sym || required_opts[:error_mode],
              file_system: filesystem,
            }.compact

            LiquidSpec.do_compile(spec.template, compile_options)
            template = LiquidSpec.ctx[:template]

            environment = deep_copy(spec.instantiate_environment)
            render_options = {
              registers: build_registers(spec, filesystem),
              strict_errors: !render_errors,
            }.compact

            actual = LiquidSpec.do_render(environment, render_options)
            { actual: actual, error: nil, template: template }
          rescue => e
            { actual: nil, error: e, template: LiquidSpec.ctx[:template] }
          end

          def build_registers(spec, filesystem = nil)
            registers = {}
            filesystem ||= spec.instantiate_filesystem
            registers[:file_system] = filesystem if filesystem
            template_factory = spec.instantiate_template_factory
            registers[:template_factory] = template_factory if template_factory
            registers
          end

          def deep_copy(obj, seen = {}.compare_by_identity)
            return seen[obj] if seen.key?(obj)

            case obj
            when Hash
              copy = obj.class.new
              seen[obj] = copy
              obj.each { |k, v| copy[deep_copy(k, seen)] = deep_copy(v, seen) }
              copy
            when Array
              copy = []
              seen[obj] = copy
              obj.each { |v| copy << deep_copy(v, seen) }
              copy
            else
              obj
            end
          end

          def print_generated_code(template, options)
            return unless template

            printed_any = false

            if options[:print_il]
              # Try various IL/bytecode methods
              il = nil
              if template.respond_to?(:il)
                il = template.il
              elsif template.respond_to?(:bytecode)
                il = template.bytecode
              elsif template.respond_to?(:instructions)
                il = template.instructions
              end

              if il
                puts "\n\e[2mIL/Bytecode:\e[0m"
                if il.is_a?(Array)
                  il.each_with_index { |instr, i| puts "  #{i}: #{instr.inspect}" }
                else
                  il.to_s.each_line { |line| puts "  #{line}" }
                end
                printed_any = true
              end
            end

            if options[:print_ruby]
              # Try various Ruby source methods
              ruby_source = nil
              if template.respond_to?(:source)
                ruby_source = template.source
              elsif template.respond_to?(:ruby_source)
                ruby_source = template.ruby_source
              elsif template.respond_to?(:generated_source)
                ruby_source = template.generated_source
              end

              if ruby_source
                puts "\n\e[2mGenerated Ruby:\e[0m"
                ruby_source.to_s.each_line.with_index(1) { |line, i| puts "  #{i.to_s.rjust(3)}: #{line}" }
                printed_any = true
              end
            end

            unless printed_any
              methods_tried = []
              methods_tried << "il, bytecode, instructions" if options[:print_il]
              methods_tried << "source, ruby_source, generated_source" if options[:print_ruby]
              puts "\n\e[2mNo generated code available (tried: #{methods_tried.join("; ")})\e[0m"
            end
          end

          def load_specs(config)
            require "liquid/spec"

            suite_id = config.suite || :all

            case suite_id
            when :all
              Liquid::Spec::Suite.defaults.flat_map do |suite|
                Liquid::Spec::SpecLoader.load_suite(suite)
              end
            else
              suite = Liquid::Spec::Suite.find(suite_id)
              return [] unless suite

              Liquid::Spec::SpecLoader.load_suite(suite)
            end
          end

          def filter_strict_only(specs)
            specs.select do |s|
              mode = s.error_mode&.to_sym
              mode.nil? || mode == :strict
            end
          end
        end
      end
    end
  end
end
