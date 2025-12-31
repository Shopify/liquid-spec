# frozen_string_literal: true

require_relative "adapter_dsl"
require "timecop"

module Liquid
  module Spec
    module CLI
      module Runner
        # Time used for all spec runs (matches liquid test suite)
        TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze
        MAX_FAILURES_DEFAULT = 10

        HELP = <<~HELP
          Usage: liquid-spec run ADAPTER [options]

          Options:
            -n, --name PATTERN    Only run specs matching PATTERN
            -s, --suite SUITE     Spec suite: all, liquid_ruby, dawn (default: from adapter)
            -v, --verbose         Show verbose output
            -l, --list            List available specs without running
            --max-failures N      Stop after N failures (default: #{MAX_FAILURES_DEFAULT})
            --no-max-failures     Run all specs regardless of failures
            -h, --help            Show this help

          Examples:
            liquid-spec run my_adapter.rb
            liquid-spec run my_adapter.rb -n assign
            liquid-spec run my_adapter.rb -s liquid_ruby -v
            liquid-spec run my_adapter.rb --no-max-failures

        HELP

        def self.run(args)
          if args.empty? || args.include?("-h") || args.include?("--help")
            puts HELP
            return
          end

          adapter_file = args.shift
          options = parse_options(args)

          unless File.exist?(adapter_file)
            $stderr.puts "Error: Adapter file not found: #{adapter_file}"
            exit 1
          end

          # Load the adapter
          LiquidSpec.reset!
          LiquidSpec.running_from_cli!
          load File.expand_path(adapter_file)

          config = LiquidSpec.config || LiquidSpec.configure

          # Override config with CLI options
          config.suite = options[:suite] if options[:suite]
          config.filter = options[:filter] if options[:filter]
          config.verbose = options[:verbose] if options[:verbose]

          if options[:list]
            list_specs(config)
          else
            run_specs(config, options)
          end
        end

        def self.parse_options(args)
          options = { max_failures: MAX_FAILURES_DEFAULT }

          while args.any?
            case args.first
            when "-n", "--name"
              args.shift
              pattern = args.shift
              options[:filter] = Regexp.new(pattern, Regexp::IGNORECASE)
            when "-s", "--suite"
              args.shift
              options[:suite] = args.shift.to_sym
            when "-v", "--verbose"
              args.shift
              options[:verbose] = true
            when "-l", "--list"
              args.shift
              options[:list] = true
            when "--max-failures"
              args.shift
              options[:max_failures] = args.shift.to_i
            when "--no-max-failures"
              args.shift
              options[:max_failures] = nil
            else
              args.shift
            end
          end

          options
        end

        def self.list_specs(config)
          specs = load_specs(config.suite)
          specs = filter_specs(specs, config.filter) if config.filter

          puts "Available specs (#{specs.size} total):"
          puts ""

          specs.group_by { |s| s.name.split("#").first }.each do |group, group_specs|
            puts "  #{group} (#{group_specs.size} specs)"
            if config.verbose
              group_specs.each do |spec|
                puts "    - #{spec.name.split('#').last}"
              end
            end
          end
        end

        def self.run_specs(config, options)
          # Run adapter setup first (loads the liquid gem)
          LiquidSpec.run_setup!

          # Now load liquid/spec components (they depend on Liquid being loaded)
          require "liquid/spec"
          require "liquid/spec/deps/liquid_ruby"
          require "liquid/spec/yaml_initializer"

          specs = load_specs(config.suite)
          specs = filter_specs(specs, config.filter) if config.filter

          if specs.empty?
            puts "No specs to run"
            return
          end

          # Show which suite is being run
          all_suites = [:liquid_ruby, :dawn]
          active_suite = config.suite

          puts "Suite: #{active_suite}"
          if active_suite != :all
            other_suites = all_suites - [active_suite]
            puts "  (other available: #{other_suites.join(', ')})"
          end
          puts ""
          puts "Running #{specs.size} specs..."
          puts ""

          passed = 0
          failed = 0
          errors = 0
          failures = []
          max_failures = options[:max_failures]
          stopped_early = false

          specs.each do |spec|
            result = run_single_spec(spec, config)

            case result[:status]
            when :pass
              passed += 1
              print "." unless config.verbose
              puts "PASS: #{spec.name}" if config.verbose
            when :fail
              failed += 1
              print "F" unless config.verbose
              puts "FAIL: #{spec.name}" if config.verbose
              failures << { spec: spec, result: result }
            when :error
              errors += 1
              print "E" unless config.verbose
              puts "ERROR: #{spec.name}" if config.verbose
              failures << { spec: spec, result: result }
            end

            if max_failures && (failed + errors) >= max_failures
              stopped_early = true
              break
            end
          end

          puts "" unless config.verbose
          puts ""

          if stopped_early
            puts "Stopped after #{max_failures} failures (#{passed} passed so far)"
            puts "Run with --no-max-failures to see all failures"
            puts ""
          else
            puts "#{passed} passed, #{failed} failed, #{errors} errors"
          end

          if failures.any?
            puts ""
            puts "Failures:"
            puts ""

            failures.each_with_index do |f, i|
              puts "#{i + 1}) #{f[:spec].name}"
              puts "   Template: #{f[:spec].template.inspect[0..80]}"
              puts "   Expected: #{f[:result][:expected].inspect[0..80]}"
              puts "   Got:      #{f[:result][:actual].inspect[0..80]}"
              if f[:result][:error]
                puts "   Error:    #{f[:result][:error].class}: #{f[:result][:error].message}"
              end
              puts ""
            end

            exit 1
          end
        end

        def self.run_single_spec(spec, config)
          Timecop.freeze(TEST_TIME) do
            # Build compile options from spec
            compile_options = {
              line_numbers: true,
              error_mode: spec.error_mode&.to_sym,
            }.compact

            template = LiquidSpec.do_compile(spec.template, compile_options)

            # Set template name if the spec specifies one and template supports it
            if spec.template_name && template.respond_to?(:name=)
              template.name = spec.template_name
            end

            # Build file system from spec
            file_system = build_file_system(spec)

            # Pass ALL spec options to the render context
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
            expected = spec.expected

            if actual == expected
              { status: :pass }
            else
              { status: :fail, expected: expected, actual: actual }
            end
          end
        rescue => e
          { status: :error, expected: spec.expected, actual: nil, error: e }
        end

        def self.build_file_system(spec)
          case spec.filesystem
          when Hash
            StubFileSystem.new(spec.filesystem)
          when nil
            # No filesystem specified - use blank which raises on any access
            Liquid::BlankFileSystem.new
          else
            spec.filesystem
          end
        end

        def self.load_specs(suite)
          # Ensure setup has run (loads liquid gem)
          LiquidSpec.run_setup!

          # Load spec components - these require Liquid to be loaded first
          require "liquid/spec"
          require "liquid/spec/deps/liquid_ruby"
          require "liquid/spec/yaml_initializer"

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
              Liquid::Spec::Source.for(path).to_a rescue []
            end
          else
            $stderr.puts "Unknown suite: #{suite}"
            $stderr.puts "Available suites: all, liquid_ruby, dawn"
            exit 1
          end
        end

        def self.filter_specs(specs, pattern)
          specs.select { |s| s.name =~ pattern }
        end
      end
    end
  end
end
