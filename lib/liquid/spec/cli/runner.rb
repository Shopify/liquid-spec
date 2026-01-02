# frozen_string_literal: true

require_relative "adapter_dsl"
require "timecop"

module Liquid
  module Spec
    module CLI
      module Runner
        # Time used for all spec runs (matches liquid test suite)
        # Frozen to a known time so date/time filters produce consistent results
        TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze
        TEST_TZ = "UTC"
        MAX_FAILURES_DEFAULT = 10

        HELP = <<~HELP
          Usage: liquid-spec run ADAPTER [options]

          Options:
            -n, --name PATTERN    Only run specs matching PATTERN
            -s, --suite SUITE     Spec suite (use 'all' for all default suites, or a specific suite name)
            -v, --verbose         Show verbose output
            -l, --list            List available specs without running
            --list-suites         List available suites
            --max-failures N      Stop after N failures (default: #{MAX_FAILURES_DEFAULT})
            --no-max-failures     Run all specs regardless of failures (not recommended)
            -h, --help            Show this help

          Examples:
            liquid-spec run my_adapter.rb
            liquid-spec run my_adapter.rb -n assign
            liquid-spec run my_adapter.rb -s liquid_ruby -v
            liquid-spec run my_adapter.rb --no-max-failures
            liquid-spec run my_adapter.rb --list-suites

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
            exit(1)
          end

          # Load the adapter
          LiquidSpec.reset!
          LiquidSpec.running_from_cli!
          load(File.expand_path(adapter_file))

          config = LiquidSpec.config || LiquidSpec.configure

          # Override config with CLI options
          config.suite = options[:suite] if options[:suite]
          config.filter = options[:filter] if options[:filter]
          config.verbose = options[:verbose] if options[:verbose]
          config.strict_only = options[:strict_only] if options[:strict_only]

          if options[:list_suites]
            list_suites(config)
          elsif options[:list]
            list_specs(config)
          else
            run_specs(config, options)
          end
        end

        def self.parse_options(args)
          options = { max_failures: MAX_FAILURES_DEFAULT }

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
            when "-v", "--verbose"
              options[:verbose] = true
            when "-l", "--list"
              options[:list] = true
            when "--list-suites"
              options[:list_suites] = true
            when "--max-failures"
              options[:max_failures] = args.shift.to_i
            when /\A--max-failures=(\d+)\z/
              options[:max_failures] = ::Regexp.last_match(1).to_i
            when "--no-max-failures"
              options[:max_failures] = nil
            end
          end

          options
        end

        def self.list_suites(config)
          # Load spec components
          LiquidSpec.run_setup!
          require "liquid/spec"
          require "liquid/spec/suite"

          puts "Available suites:"
          puts ""

          Liquid::Spec::Suite.all.each do |suite|
            default_marker = suite.default? ? " (default)" : ""
            runnable = suite.runnable_with?(config.features)
            status = runnable ? "" : " [missing features: #{suite.missing_features(config.features).join(", ")}]"

            puts "  #{suite.id}#{default_marker}#{status}"
            puts "    #{suite.description}" if suite.description && config.verbose
            if config.verbose && suite.required_features.any?
              puts "    Required features: #{suite.required_features.join(", ")}"
            end
          end
        end

        def self.list_specs(config)
          specs = load_specs(config)
          specs = filter_specs(specs, config.filter) if config.filter

          puts "Available specs (#{specs.size} total):"
          puts ""

          specs.group_by { |s| s.name.split("#").first }.each do |group, group_specs|
            puts "  #{group} (#{group_specs.size} specs)"
            next unless config.verbose

            group_specs.each do |spec|
              puts "    - #{spec.name.split("#").last}"
            end
          end
        end

        def self.run_specs(config, options)
          # Set timezone BEFORE loading anything else to ensure consistent behavior
          original_tz = ENV["TZ"]
          ENV["TZ"] = TEST_TZ

          # Freeze time BEFORE adapter setup so adapters see frozen time
          Timecop.freeze(TEST_TIME) do
            run_specs_frozen(config, options)
          end
        ensure
          ENV["TZ"] = original_tz
        end

        def self.run_specs_frozen(config, options)
          # Run adapter setup first (loads the liquid gem)
          LiquidSpec.run_setup!

          # Now load liquid/spec components (they depend on Liquid being loaded)
          require "liquid/spec"
          require "liquid/spec/suite"
          require "liquid/spec/deps/liquid_ruby"
          require "liquid/spec/yaml_initializer"

          specs = load_specs(config)
          specs = filter_specs(specs, config.filter) if config.filter
          specs = filter_strict_only(specs) if config.strict_only

          if specs.empty?
            puts "No specs to run"
            return
          end

          # Show what we're running
          features = config.features

          puts "Features: #{features.join(", ")}"
          puts ""

          # Collect suites to run
          suites_to_run = Liquid::Spec::Suite.all.select { |s| s.default? && s.runnable_with?(features) }
          skipped_suites = Liquid::Spec::Suite.all.select { |s| s.default? && !s.runnable_with?(features) }

          total_passed = 0
          total_failed = 0
          total_errors = 0
          all_failures = []
          max_failures = options[:max_failures]
          stopped_early = false

          # Run each suite with its own header
          suites_to_run.each do |suite|
            break if stopped_early

            suite_specs = suite.specs
            suite_specs = filter_specs(suite_specs, config.filter) if config.filter

            next if suite_specs.empty?

            suite_name_padded = "#{suite.name} ".ljust(40, ".")
            print("#{suite_name_padded} ")
            $stdout.flush

            passed = 0
            failed = 0
            errors = 0

            suite_specs.each do |spec|
              result = run_single_spec(spec, config)

              case result[:status]
              when :pass
                passed += 1
              when :fail
                failed += 1
                all_failures << { spec: spec, result: result }
              when :error
                errors += 1
                all_failures << { spec: spec, result: result }
              end

              if max_failures && (total_failed + total_errors + failed + errors) >= max_failures
                stopped_early = true
                break
              end
            end

            # Show result
            if failed + errors == 0
              puts "#{passed}/#{suite_specs.size} passed"
            else
              puts "#{passed}/#{suite_specs.size} passed, #{failed} failed, #{errors} errors"
            end

            total_passed += passed
            total_failed += failed
            total_errors += errors
          end

          # Show skipped suites
          skipped_suites.each do |suite|
            missing = suite.missing_features(features)
            suite_name_padded = "#{suite.name} ".ljust(40, ".")
            puts "#{suite_name_padded} skipped (needs #{missing.join(", ")})"
          end

          puts ""

          if stopped_early
            puts "Stopped after #{max_failures} failures (#{total_passed} passed so far)"
            puts "Run with --no-max-failures to see all failures"
            puts ""
          else
            puts "Total: #{total_passed} passed, #{total_failed} failed, #{total_errors} errors"
          end

          # Use all_failures for the failure report
          failures = all_failures

          if failures.any?
            puts ""
            puts "Failures:"
            puts ""

            # Collect hints grouped by source
            hints_by_source = {}
            failures.each_with_index do |f, i|
              puts "#{i + 1}) #{f[:spec].name}"
              puts "   Template: #{f[:spec].template.inspect[0..80]}"
              puts "   Expected: #{f[:result][:expected].inspect[0..80]}"
              puts "   Got:      #{f[:result][:actual].inspect[0..80]}"
              if f[:result][:error]
                puts "   Error:    #{f[:result][:error].class}: #{f[:result][:error].message}"
              end
              puts ""

              # Collect hints by source (source_hint) and spec-level hints
              source_hint = f[:spec].source_hint
              spec_hint = f[:spec].hint

              if source_hint
                hints_by_source[source_hint] ||= []
                hints_by_source[source_hint] << spec_hint if spec_hint
              elsif spec_hint
                hints_by_source[nil] ||= []
                hints_by_source[nil] << spec_hint
              end
            end

            # Print hints grouped by source, unique and limited to 5
            if hints_by_source.any?
              puts ""
              puts "Hints:"
              hints_by_source.each do |source_hint, spec_hints|
                if source_hint
                  puts ""
                  puts "  #{source_hint.strip.gsub("\n", " ")}"
                end
                unique_spec_hints = spec_hints.uniq.compact.first(5)
                unique_spec_hints.each do |hint|
                  puts "    - #{hint.strip.gsub("\n", " ")}"
                end
              end
            end

            exit(1)
          end
        end

        def self.run_single_spec(spec, _config)
          # Time is already frozen at the run_specs level

          # Merge source-level required_options with spec-level options
          # Spec-level options take precedence
          required_opts = spec.source_required_options || {}
          render_errors = spec.render_errors || required_opts[:render_errors]

          # Build compile options from spec (spec values override required_options)
          compile_options = {
            line_numbers: true,
            error_mode: spec.error_mode&.to_sym || required_opts[:error_mode],
          }.compact

          template = begin
            LiquidSpec.do_compile(spec.template, compile_options)
          rescue Liquid::SyntaxError => e
            # If render_errors is true, treat compile errors as rendered output
            if render_errors
              return compare_result(e.message, spec.expected)
            else
              raise
            end
          end

          # Set template name if the spec specifies one and template supports it
          if spec.template_name && template.respond_to?(:name=)
            template.name = spec.template_name
          end

          # Build assigns (deep copy to avoid mutation between tests)
          assigns = deep_copy(spec.environment || {})

          # Build render options
          render_options = {
            registers: build_registers(spec),
            strict_errors: !render_errors,
            exception_renderer: spec.exception_renderer,
          }.compact

          actual = LiquidSpec.do_render(template, assigns, render_options)
          compare_result(actual, spec.expected)
        rescue Exception => e
          # Catch all exceptions including SyntaxError
          { status: :error, expected: spec.expected, actual: nil, error: e }
        end

        def self.compare_result(actual, expected)
          if actual == expected
            { status: :pass }
          else
            { status: :fail, expected: expected, actual: actual }
          end
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

        def self.build_registers(spec)
          registers = {}
          registers[:file_system] = build_file_system(spec)
          registers[:template_factory] = spec.template_factory if spec.template_factory
          registers
        end

        def self.deep_copy(obj, seen = {}.compare_by_identity)
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

        def self.load_specs(config)
          # Ensure setup has run (loads liquid gem)
          LiquidSpec.run_setup!

          # Load spec components - these require Liquid to be loaded first
          require "liquid/spec"
          require "liquid/spec/suite"
          require "liquid/spec/deps/liquid_ruby"
          require "liquid/spec/yaml_initializer"

          suite_id = config.suite
          features = config.features

          case suite_id
          when :all
            # Load all default suites that are runnable with the adapter's features
            Liquid::Spec::Suite.defaults.select { |s| s.runnable_with?(features) }.flat_map(&:specs)
          else
            suite = Liquid::Spec::Suite.find(suite_id)
            if suite.nil?
              available = Liquid::Spec::Suite.all.map(&:id).join(", ")
              $stderr.puts "Unknown suite: #{suite_id}"
              $stderr.puts "Available suites: all, #{available}"
              exit(1)
            end

            unless suite.runnable_with?(features)
              missing = suite.missing_features(features)
              $stderr.puts "Suite '#{suite_id}' requires features not supported by this adapter:"
              $stderr.puts "  Missing: #{missing.join(", ")}"
              $stderr.puts "  Adapter features: #{features.join(", ")}"
              $stderr.puts ""
              $stderr.puts "Add the required features to your adapter configuration:"
              $stderr.puts "  LiquidSpec.configure do |config|"
              $stderr.puts "    config.features = #{(features + missing).inspect}"
              $stderr.puts "  end"
              exit(1)
            end

            suite.specs
          end
        end

        def self.filter_specs(specs, pattern)
          specs.select { |s| s.name =~ pattern }
        end

        # Filter to only specs that work in strict mode
        # Includes specs with error_mode: :strict or nil (default is strict)
        def self.filter_strict_only(specs)
          specs.select do |s|
            mode = s.error_mode&.to_sym
            mode.nil? || mode == :strict
          end
        end
      end
    end
  end
end
