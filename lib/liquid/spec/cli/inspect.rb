# frozen_string_literal: true

require_relative "adapter_dsl"
require "timecop"

module Liquid
  module Spec
    module CLI
      # Inspect command - shows detailed info about a specific test
      module Inspect
        TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze

        HELP = <<~HELP
          Usage: liquid-spec inspect ADAPTER -n PATTERN

          Shows detailed information about matching specs including:
          - Full template source
          - Environment/assigns
          - Expected output (from reference implementation)
          - Your adapter's output
          - Difference if any

          Options:
            -n, --name PATTERN    Spec name pattern (required)
            -s, --suite SUITE     Spec suite: all, liquid_ruby, dawn
            --strict              Only inspect specs with error_mode: strict
            -h, --help            Show this help

          Examples:
            liquid-spec inspect my_adapter.rb -n "case.*empty"
            liquid-spec inspect my_adapter.rb -n "for loop first"

        HELP

        def self.run(args)
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

          inspect_specs(config)
        end

        def self.parse_options(args)
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
            end
          end

          options
        end

        def self.inspect_specs(config)
          # Run setup first
          LiquidSpec.run_setup!

          # Load spec components
          require "liquid/spec"
          require "liquid/spec/deps/liquid_ruby"
          require "liquid/spec/yaml_initializer"

          specs = load_specs(config.suite)
          specs = specs.select { |s| s.name =~ config.filter }
          specs = Runner.filter_strict_only(specs) if config.strict_only

          if specs.empty?
            puts "No specs matching pattern: #{config.filter.inspect}"
            return
          end

          puts "Found #{specs.size} matching spec(s)"
          puts "=" * 80

          specs.each_with_index do |spec, idx|
            puts "" if idx > 0
            inspect_single_spec(spec, config)
            puts "=" * 80
          end
        end

        def self.inspect_single_spec(spec, config)
          puts "\e[1m#{spec.name}\e[0m"

          # Show hint if present
          if spec.hint && !spec.hint.empty?
            puts "\e[36m#{spec.hint.strip}\e[0m"
          end

          # Show complexity if present
          if spec.complexity
            puts "\e[2mComplexity:\e[0m #{spec.complexity}"
          end

          puts ""
          puts "-" * 80

          puts "\n\e[2mTemplate:\e[0m"
          if spec.template.include?("\n")
            spec.template.each_line { |line| puts "  #{line}" }
          else
            puts "  #{spec.template}"
          end

          if spec.environment && !spec.environment.empty?
            puts "\n\e[2mEnvironment:\e[0m"
            spec.environment.each do |key, value|
              puts "  #{key}: #{value.inspect}"
            end
          end

          if spec.filesystem.is_a?(Hash) && !spec.filesystem.empty?
            puts "\n\e[2mFilesystem:\e[0m"
            spec.filesystem.each do |name, content|
              puts "  #{name}:"
              content.each_line { |l| puts "    #{l}" }
            end
          end

          puts "\n\e[2mExpected:\e[0m"
          print_value(spec.expected)

          puts "\n\e[2mActual:\e[0m"
          Timecop.freeze(TEST_TIME) do
            result = run_with_adapter(spec, config)
            if result[:error]
              puts "  \e[31mERROR:\e[0m #{result[:error].class}: #{result[:error].message}"
              result[:error].backtrace.first(5).each { |line| puts "    #{line}" }
            else
              print_value(result[:actual])
            end

            puts ""
            if result[:actual] == spec.expected
              puts "\e[32m✓ PASS\e[0m"
            else
              puts "\e[31m✗ FAIL\e[0m"
              if result[:actual] && spec.expected
                diff = string_diff(spec.expected, result[:actual])
                puts "\n\e[2mDiff:\e[0m #{diff}" if diff
              end
            end
          end
        end

        def self.print_value(value)
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

        def self.string_diff(expected, actual)
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

        def self.run_with_adapter(spec, config)
          compile_options = {
            line_numbers: true,
            error_mode: spec.error_mode&.to_sym,
          }.compact

          template = LiquidSpec.do_compile(spec.template, compile_options)
          template.name = spec.template_name if spec.template_name && template.respond_to?(:name=)

          file_system = build_file_system(spec)

          context = {
            environment: spec.environment || {},
            file_system: file_system,
            template_factory: spec.template_factory,
            exception_renderer: spec.exception_renderer,
            error_mode: spec.error_mode&.to_sym,
            render_errors: spec.render_errors,
            context_klass: spec.context_klass,
          }

          actual = LiquidSpec.do_render(template, context)
          { actual: actual }
        rescue => e
          { actual: nil, error: e }
        end

        def self.build_file_system(spec)
          case spec.filesystem
          when Hash
            StubFileSystem.new(spec.filesystem)
          when nil
            Liquid::BlankFileSystem.new
          else
            spec.filesystem
          end
        end

        def self.load_specs(suite)
          case suite
          when :all
            Liquid::Spec.all_sources.flat_map(&:to_a)
          when :liquid_ruby
            liquid_ruby_path = File.join(Liquid::Spec::SPEC_FILES.sub("**/*{.yml,.txt}", ""), "liquid_ruby", "*.yml")
            Dir[liquid_ruby_path].flat_map do |path|
              Liquid::Spec::Source.for(path).to_a
            end
          when :dawn
            dawn_path = File.join(Liquid::Spec::SPEC_FILES.sub("**/*{.yml,.txt}", ""), "dawn", "*")
            Dir[dawn_path].select { |p| File.directory?(p) }.flat_map do |path|
              Liquid::Spec::Source.for(path).to_a
            rescue
              []
            end
          else
            []
          end
        end
      end
    end
  end
end
