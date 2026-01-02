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
            -n, --name PATTERN    Only run specs matching PATTERN (use /regex/ for regex)
            -s, --suite SUITE     Spec suite (use 'all' for all default suites, or a specific suite name)
            --add-specs=GLOB      Add additional spec files (can be used multiple times)
            -c, --compare         Compare adapter output against reference liquid-ruby
            -v, --verbose         Show verbose output
            -l, --list            List available specs without running
            --list-suites         List available suites
            --max-failures N      Stop after N failures (default: #{MAX_FAILURES_DEFAULT})
            --no-max-failures     Run all specs regardless of failures (not recommended)
            -h, --help            Show this help

          Examples:
            liquid-spec run my_adapter.rb
            liquid-spec run my_adapter.rb -n assign
            liquid-spec run my_adapter.rb -n "/test_.*filter/"
            liquid-spec run my_adapter.rb -s liquid_ruby -v
            liquid-spec run my_adapter.rb --compare
            liquid-spec run my_adapter.rb --add-specs="my_specs/*.yml"
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
          options = { max_failures: MAX_FAILURES_DEFAULT, add_specs: [] }

          while args.any?
            arg = args.shift
            case arg
            when "-n", "--name"
              pattern = args.shift
              options[:filter] = parse_filter_pattern(pattern)
            when /\A--name=(.+)\z/, /\A-n(.+)\z/
              options[:filter] = parse_filter_pattern(::Regexp.last_match(1))
            when "-s", "--suite"
              options[:suite] = args.shift.to_sym
            when /\A--suite=(.+)\z/
              options[:suite] = ::Regexp.last_match(1).to_sym
            when "--add-specs"
              options[:add_specs] << args.shift
            when /\A--add-specs=(.+)\z/
              options[:add_specs] << ::Regexp.last_match(1)
            when "--strict"
              options[:strict_only] = true
            when "-c", "--compare"
              options[:compare] = true
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
            if options[:compare]
              run_specs_compare(config, options)
            else
              run_specs_frozen(config, options)
            end
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

          # Collect suites to run (basics first, then others alphabetically)
          # When a specific suite is requested via -s, run that suite regardless of default?
          specific_suite = config.suite != :all ? Liquid::Spec::Suite.find(config.suite) : nil

          if specific_suite
            suites_to_run = [specific_suite]
            skipped_suites = []
          else
            suites_to_run = Liquid::Spec::Suite.all
              .select { |s| s.default? && s.runnable_with?(features) }
              .sort_by { |s| s.id == :basics ? "" : s.id.to_s }
            skipped_suites = Liquid::Spec::Suite.all.select { |s| s.default? && !s.runnable_with?(features) }
          end

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
            suite_specs = filter_by_features(suite_specs, features)
            suite_specs = sort_by_complexity(suite_specs)

            next if suite_specs.empty?

            suite_name_padded = "#{suite.name} ".ljust(40, ".")
            print("#{suite_name_padded} ")
            $stdout.flush

            passed = 0
            failed = 0
            errors = 0

            suite_specs.each do |spec|
              begin
                result = run_single_spec(spec, config)
              rescue SystemExit, Interrupt, SignalException
                raise
              rescue Exception => e
                # Catch all exceptions including those from Ruby::Box isolation
                result = { status: :error, error: e }
              end

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

          # Run additional specs if provided
          if options[:add_specs] && !options[:add_specs].empty? && !stopped_early
            additional_specs = load_additional_specs(options[:add_specs])
            additional_specs = filter_specs(additional_specs, config.filter) if config.filter
            additional_specs = filter_by_features(additional_specs, features)
            additional_specs = sort_by_complexity(additional_specs)

            if additional_specs.any?
              suite_name_padded = "Additional Specs ".ljust(40, ".")
              print("#{suite_name_padded} ")
              $stdout.flush

              passed = 0
              failed = 0
              errors = 0

              additional_specs.each do |spec|
                begin
                  result = run_single_spec(spec, config)
                rescue SystemExit, Interrupt, SignalException
                  raise
                rescue Exception => e
                  result = { status: :error, error: e }
                end

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

              if failed + errors == 0
                puts "#{passed}/#{additional_specs.size} passed"
              else
                puts "#{passed}/#{additional_specs.size} passed, #{failed} failed, #{errors} errors"
              end

              total_passed += passed
              total_failed += failed
              total_errors += errors
            end
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

            # Track which hints we've already shown (dedup)
            shown_hints = Set.new

            failures.each_with_index do |f, i|
              puts "#{i + 1}) #{f[:spec].name}"
              puts "   Template: #{f[:spec].template.inspect[0..80]}"
              puts "   Expected: #{f[:result][:expected].inspect[0..80]}"
              puts "   Got:      #{f[:result][:actual].inspect[0..80]}"
              if f[:result][:error]
                puts "   Error:    #{f[:result][:error].class}: #{f[:result][:error].message}"
              end

              # Show hint inline, but only first occurrence of each unique hint
              effective_hint = f[:spec].effective_hint
              if effective_hint && !shown_hints.include?(effective_hint)
                shown_hints << effective_hint
                puts ""
                puts "   Hint: #{effective_hint.strip.gsub("\n", "\n         ")}"
              end

              puts ""
            end

            exit(1)
          end
        end

        # Compare mode: run specs against both reference liquid-ruby and the adapter
        def self.run_specs_compare(config, options)
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

          features = config.features
          puts "Compare mode: checking adapter against reference liquid-ruby"
          puts "Features: #{features.join(", ")}"
          puts ""

          # Collect suites to run
          specific_suite = config.suite != :all ? Liquid::Spec::Suite.find(config.suite) : nil

          suites_to_run = if specific_suite
            [specific_suite]
          else
            Liquid::Spec::Suite.all
              .select { |s| s.default? && s.runnable_with?(features) }
              .sort_by { |s| s.id == :basics ? "" : s.id.to_s }
          end

          total_same = 0
          total_different = 0
          total_errors = 0
          all_differences = []
          max_failures = options[:max_failures]
          stopped_early = false

          suites_to_run.each do |suite|
            break if stopped_early

            suite_specs = suite.specs
            suite_specs = filter_specs(suite_specs, config.filter) if config.filter
            suite_specs = filter_by_features(suite_specs, features)
            suite_specs = sort_by_complexity(suite_specs)

            next if suite_specs.empty?

            suite_name_padded = "#{suite.name} ".ljust(40, ".")
            print("#{suite_name_padded} ")
            $stdout.flush

            same = 0
            different = 0
            errors = 0

            suite_specs.each do |spec|
              begin
                result = compare_single_spec(spec, config)
              rescue SystemExit, Interrupt, SignalException
                raise
              rescue Exception => e
                # Catch all exceptions including those from Ruby::Box isolation
                result = { status: :error, error: e }
              end

              case result[:status]
              when :same
                same += 1
              when :different
                different += 1
                all_differences << { spec: spec, result: result }
              when :error
                errors += 1
                all_differences << { spec: spec, result: result }
              end

              if max_failures && (total_different + total_errors + different + errors) >= max_failures
                stopped_early = true
                break
              end
            end

            if different + errors == 0
              puts "#{same}/#{suite_specs.size} match"
            else
              puts "#{same}/#{suite_specs.size} match, \e[33m#{different} different\e[0m, #{errors} errors"
            end

            total_same += same
            total_different += different
            total_errors += errors
          end

          puts ""

          if stopped_early
            puts "Stopped after #{max_failures} differences (#{total_same} matching so far)"
            puts "Run with --no-max-failures to see all differences"
            puts ""
          elsif total_different == 0 && total_errors == 0
            puts "\e[32mTotal: #{total_same} specs match reference implementation\e[0m"
          else
            puts "Total: #{total_same} match, \e[33m#{total_different} different\e[0m, #{total_errors} errors"
          end

          if all_differences.any?
            puts ""
            puts "\e[33mDifferences from reference liquid-ruby:\e[0m"
            puts ""

            all_differences.each_with_index do |d, i|
              puts "#{i + 1}) #{d[:spec].name}"
              puts "   Template: #{d[:spec].template.inspect[0..80]}"
              if d[:result][:reference_error]
                puts "   Reference: \e[31mERROR\e[0m #{d[:result][:reference_error].class}: #{d[:result][:reference_error].message[0..60]}"
              else
                puts "   Reference: #{d[:result][:reference].inspect[0..80]}"
              end
              if d[:result][:adapter_error]
                puts "   Adapter:   \e[31mERROR\e[0m #{d[:result][:adapter_error].class}: #{d[:result][:adapter_error].message[0..60]}"
              else
                puts "   Adapter:   #{d[:result][:adapter].inspect[0..80]}"
              end
              if d[:spec].hint
                puts "   Hint: #{d[:spec].hint.strip.tr("\n", " ")[0..80]}"
              end
              puts ""
            end

            puts ""
            puts "\e[1;33m#{"=" * 60}\e[0m"
            puts "\e[1;33m  #{all_differences.size} DIFFERENCES DETECTED\e[0m"
            puts "\e[1;33m#{"=" * 60}\e[0m"
            puts ""
            puts "These specs show behavioral differences between your implementation"
            puts "and the reference liquid-ruby. This could indicate:"
            puts "  - Bugs in your implementation"
            puts "  - Intentional differences (document these!)"
            puts "  - Missing features"
            puts ""
            puts "Please contribute documented differences to liquid-spec:"
            puts "  \e[4mhttps://github.com/Shopify/liquid-spec\e[0m"
            puts ""

            exit(1)
          end
        end

        def self.compare_single_spec(spec, _config)
          # Build compile/render options
          required_opts = spec.source_required_options || {}
          render_errors = spec.render_errors || required_opts[:render_errors] || spec.expects_render_error?

          compile_options = {
            line_numbers: true,
            error_mode: spec.error_mode&.to_sym || required_opts[:error_mode],
          }.compact

          assigns = deep_copy(spec.environment || {})
          render_options = {
            registers: build_registers(spec),
            strict_errors: !render_errors,
            exception_renderer: spec.exception_renderer,
          }.compact

          # Run reference implementation (catches all errors internally)
          reference_result, reference_error = run_reference_spec(spec, compile_options, assigns, render_options)

          # Run adapter implementation (catches all errors internally)
          adapter_result, adapter_error = run_adapter_spec(spec, compile_options, assigns, render_options)

          # Compare results
          if reference_error && adapter_error
            # Both errored - check if same error type
            if reference_error.class == adapter_error.class
              { status: :same }
            else
              {
                status: :different,
                reference: nil,
                reference_error: reference_error,
                adapter: nil,
                adapter_error: adapter_error,
              }
            end
          elsif reference_error
            {
              status: :different,
              reference: nil,
              reference_error: reference_error,
              adapter: adapter_result,
              adapter_error: nil,
            }
          elsif adapter_error
            {
              status: :different,
              reference: reference_result,
              reference_error: nil,
              adapter: nil,
              adapter_error: adapter_error,
            }
          elsif reference_result == adapter_result
            { status: :same }
          else
            {
              status: :different,
              reference: reference_result,
              reference_error: nil,
              adapter: adapter_result,
              adapter_error: nil,
            }
          end
        rescue StandardError => e
          { status: :error, error: e }
        end

        def self.run_reference_spec(spec, _compile_options, assigns, render_options)
          # Always run reference in strict mode for consistent comparison
          strict_compile_options = { line_numbers: true, error_mode: :strict }

          # Compile with reference Liquid in strict mode
          template = Liquid::Template.parse(spec.template, **strict_compile_options)

          # Set template name if specified
          template.name = spec.template_name if spec.template_name && template.respond_to?(:name=)

          # Build context with strict errors
          context = Liquid::Context.build(
            static_environments: assigns,
            registers: Liquid::Registers.new(render_options[:registers] || {}),
            rethrow_errors: true,
          )
          context.exception_renderer = render_options[:exception_renderer] if render_options[:exception_renderer]

          ref_result = template.render(context)
          [ref_result, nil]
        rescue SystemExit, Interrupt, SignalException
          raise
        rescue Exception => e
          [nil, e]
        end

        def self.run_adapter_spec(spec, compile_options, assigns, render_options)
          adapter_result = nil
          adapter_error = nil
          begin
            template = LiquidSpec.do_compile(spec.template, compile_options)
            template.name = spec.template_name if spec.template_name && template.respond_to?(:name=)
            adapter_result = LiquidSpec.do_render(template, assigns, render_options)
          rescue SystemExit, Interrupt, SignalException
            raise
          rescue Exception => e
            adapter_error = e
          end
          [adapter_result, adapter_error]
        end

        def self.run_single_spec(spec, _config)
          # Time is already frozen at the run_specs level

          # Merge source-level required_options with spec-level options
          # Spec-level options take precedence
          required_opts = spec.source_required_options || {}
          render_errors = spec.render_errors || required_opts[:render_errors] || spec.expects_render_error?

          # Build compile options from spec (spec values override required_options)
          compile_options = {
            line_numbers: true,
            error_mode: spec.error_mode&.to_sym || required_opts[:error_mode],
          }.compact

          begin
            template = LiquidSpec.do_compile(spec.template, compile_options)
          rescue Liquid::SyntaxError => e
            # If spec expects a parse error, check against patterns
            if spec.expects_parse_error?
              return check_error_patterns(e, spec.error_patterns(:parse_error), "parse_error")
            end
            # If render_errors is true, treat compile errors as rendered output
            if render_errors
              return compare_result(e.message, spec.expected)
            else
              raise
            end
          end

          # If we expected a parse error but didn't get one, that's a failure
          if spec.expects_parse_error?
            return {
              status: :fail,
              expected: "parse_error matching #{spec.error_patterns(:parse_error).map(&:inspect).join(", ")}",
              actual: "no error (template parsed successfully)",
            }
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

          begin
            actual = LiquidSpec.do_render(template, assigns, render_options)
          rescue StandardError => e
            # If spec expects a render error, check against patterns
            if spec.expects_render_error?
              return check_error_patterns(e, spec.error_patterns(:render_error), "render_error")
            end

            raise
          end

          # If we expected a render error but didn't get one, that's a failure
          if spec.expects_render_error?
            return {
              status: :fail,
              expected: "render_error matching #{spec.error_patterns(:render_error).map(&:inspect).join(", ")}",
              actual: "no error (rendered: #{actual.inspect})",
            }
          end

          # If spec uses output patterns, match against them instead of exact match
          if spec.expects_output_patterns?
            return check_output_patterns(actual, spec.error_patterns(:output))
          end

          compare_result(actual, spec.expected)
        rescue StandardError => e
          # Catch standard errors (not SystemExit, Interrupt, etc.)
          { status: :error, expected: spec.expected, actual: nil, error: e }
        end

        def self.check_error_patterns(error, patterns, error_type)
          message = error.message
          failed_patterns = patterns.reject { |pattern| pattern.match?(message) }

          if failed_patterns.empty?
            { status: :pass }
          else
            {
              status: :fail,
              expected: "#{error_type} matching #{failed_patterns.map(&:inspect).join(", ")}",
              actual: "#{error.class}: #{message}",
            }
          end
        end

        def self.check_output_patterns(output, patterns)
          failed_patterns = patterns.reject { |pattern| pattern.match?(output) }

          if failed_patterns.empty?
            { status: :pass }
          else
            {
              status: :fail,
              expected: "output matching #{patterns.map(&:inspect).join(", ")}",
              actual: output,
            }
          end
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

        # Load additional specs from glob patterns
        def self.load_additional_specs(globs)
          specs = []
          globs.each do |glob|
            Dir[glob].each do |path|
              source = Liquid::Spec::Source.for(path)
              specs.concat(source.to_a)
            rescue => e
              $stderr.puts "Warning: Could not load #{path}: #{e.message}"
            end
          end
          specs
        end

        # Filter specs by required features
        def self.filter_by_features(specs, features)
          specs.select { |s| s.runnable_with?(features) }
        end

        # Parse a filter pattern, supporting /regex/ syntax
        # Returns a Regexp object
        #
        # Examples:
        #   "assign"        -> case-insensitive match (backward compatible)
        #   "/test_.*/"     -> case-sensitive regex
        #   "/test_.*/i"    -> case-insensitive regex
        def self.parse_filter_pattern(pattern)
          if pattern =~ %r{\A/(.+)/([imx]*)\z}
            # Regex syntax: /pattern/ or /pattern/flags
            regex_str = ::Regexp.last_match(1)
            flags = ::Regexp.last_match(2)
            options = 0
            options |= Regexp::IGNORECASE if flags.include?("i")
            options |= Regexp::MULTILINE if flags.include?("m")
            options |= Regexp::EXTENDED if flags.include?("x")
            Regexp.new(regex_str, options)
          else
            # Plain string: case-insensitive regex (backward compatible)
            Regexp.new(pattern, Regexp::IGNORECASE)
          end
        end

        # Filter to only specs that work in strict mode
        # Includes specs with error_mode: :strict or nil (default is strict)
        def self.filter_strict_only(specs)
          specs.select do |s|
            mode = s.error_mode&.to_sym
            mode.nil? || mode == :strict
          end
        end

        # Sort specs by complexity (lower first), specs without complexity come last
        def self.sort_by_complexity(specs)
          specs.sort_by do |s|
            # Specs with complexity sort by it, specs without go to the end (infinity)
            s.complexity || Float::INFINITY
          end
        end
      end
    end
  end
end
