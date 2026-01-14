# frozen_string_literal: true

require_relative "adapter_dsl"
require_relative "../time_freezer"
require "json"
require "set"

module Liquid
  module Spec
    module CLI
      module Runner
        # Time used for all spec runs (matches liquid test suite)
        TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze
        TEST_TZ = "UTC"
        MAX_FAILURES_DEFAULT = 10
        RESULTS_LOG_DIR = "/tmp"

        # Manages known failure patterns (exact match only)
        class KnownFailures
          def initialize
            @names = Set.new
          end

          # Load names from a file (one per line, # comments, blank lines ignored)
          def load_file(path)
            return unless path && File.exist?(path)

            File.readlines(path).each do |line|
              add(line.strip)
            end
          end

          # Load names from an array of strings
          def load_patterns(list)
            Array(list).each { |name| add(name.to_s) }
          end

          def add(name)
            return if name.empty? || name.start_with?("#")

            @names << name
          end

          def known_failure?(spec_name)
            @names.include?(spec_name.to_s)
          end

          def empty?
            @names.empty?
          end

          def size
            @names.size
          end
        end

        HELP = <<~HELP
          Usage: liquid-spec run ADAPTER [options]

          Options:
            -n, --name PATTERN    Only run specs matching PATTERN (use /regex/ for regex)
            -s, --suite SUITE     Spec suite (use 'all' for all default suites, or a specific suite name)
            --add-specs=GLOB      Add additional spec files (can be used multiple times)
            --known-failures=FILE File containing known failure patterns (one per line)
            --command=CMD         Command to run subprocess (for JSON-RPC adapters)
            --timeout=SECS        Timeout in seconds for JSON-RPC requests (default: 2)
            -c, --compare         Compare adapter output against reference liquid-ruby
            -b, --bench           Run timing suites as benchmarks (measure iterations/second)
            --profile             Profile with StackProf (use with --bench), outputs to /tmp/
            -v, --verbose         Show verbose output
            -l, --list            List available specs without running
            --list-suites         List available suites
            --max-failures N      Stop after N failures (default: #{MAX_FAILURES_DEFAULT})
            --no-max-failures     Run all specs regardless of failures (not recommended)
            -h, --help            Show this help

          Known Failures File Format:
            - One spec name per line (exact match)
            - Lines starting with # are comments
            - Blank lines are ignored

          Exit codes:
            0 - All specs pass (known failures may fail)
            1 - Unexpected failures, or known failures now pass (stale entries)

          Examples:
            liquid-spec run my_adapter.rb
            liquid-spec run my_adapter.rb -n assign
            liquid-spec run my_adapter.rb -n "/test_.*filter/"
            liquid-spec run my_adapter.rb -s liquid_ruby -v
            liquid-spec run my_adapter.rb --compare
            liquid-spec run my_adapter.rb --add-specs="my_specs/*.yml"
            liquid-spec run my_adapter.rb --list-suites
            liquid-spec run my_adapter.rb -s benchmarks --bench
            liquid-spec run my_adapter.rb --known-failures=known_failures.txt

        HELP

        class << self
          def run(args)
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

            # Pass CLI options to adapter (for JSON-RPC --command flag, etc.)
            LiquidSpec.cli_options = {
              command: options[:command],
              timeout: options[:timeout],
            }.compact

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

          def parse_options(args)
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
              when "--known-failures"
                options[:known_failures_file] = args.shift
              when /\A--known-failures=(.+)\z/
                options[:known_failures_file] = ::Regexp.last_match(1)
              when "-c", "--compare"
                options[:compare] = true
              when "-b", "--bench"
                options[:bench] = true
              when "--profile"
                options[:profile] = true
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
              when "--command"
                options[:command] = args.shift
              when /\A--command=(.+)\z/
                options[:command] = ::Regexp.last_match(1)
              when "--timeout"
                options[:timeout] = args.shift.to_i
              when /\A--timeout=(\d+)\z/
                options[:timeout] = ::Regexp.last_match(1).to_i
              end
            end

            options
          end

          def list_suites(config)
            # Load spec components
            LiquidSpec.run_setup!
            require "liquid/spec"

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

          def list_specs(config)
            LiquidSpec.run_setup!
            require "liquid/spec"

            specs = load_specs(config)
            specs = filter_specs(specs, config.filter) if config.filter

            puts "Available specs (#{specs.size} total):"
            puts ""

            specs.group_by { |s| s.name.to_s.split("#").first }.each do |group, group_specs|
              puts "  #{group} (#{group_specs.size} specs)"
              next unless config.verbose

              group_specs.each do |spec|
                puts "    - #{spec.name.to_s.split("#").last}"
              end
            end
          end

          def run_specs(config, options)
            # Capture real time for run_id before freezing
            run_id = Time.now.strftime("%Y%m%d_%H%M%S")

            # Set timezone BEFORE loading anything else
            original_tz = ENV["TZ"]
            ENV["TZ"] = TEST_TZ

            # Freeze time BEFORE adapter setup
            TimeFreezer.freeze(TEST_TIME) do
              if options[:compare]
                run_specs_compare(config, options)
              else
                run_specs_frozen(config, options, run_id)
              end
            end
          ensure
            ENV["TZ"] = original_tz
          end

          def run_specs_frozen(config, options, run_id)
            # Run adapter setup first (loads the liquid gem)
            LiquidSpec.run_setup!

            # Load spec infrastructure
            require "liquid/spec"
            require "liquid/spec/deps/liquid_ruby"

            specs = load_specs(config)
            specs = filter_specs(specs, config.filter) if config.filter
            specs = filter_strict_only(specs) if config.strict_only

            if specs.empty?
              puts "No specs to run"
              return
            end

            features = config.features
            puts "Features: #{features.join(", ")}"

            # Initialize known failures matcher
            known_failures = KnownFailures.new
            known_failures.load_file(options[:known_failures_file])
            known_failures.load_patterns(config.known_failures)

            unless known_failures.empty?
              puts "Known failures: #{known_failures.size} patterns loaded"
            end
            puts ""

            # Group specs by suite
            suites_to_run = determine_suites(config, features)

            # Check if --bench flag is provided and any suite has timings enabled
            if options[:bench]
              benchmark_suites = suites_to_run.select(&:timings?)
              if benchmark_suites.any?
                run_benchmark_suites(benchmark_suites, config, options)
                suites_to_run = suites_to_run.reject(&:timings?)
                return if suites_to_run.empty?
              end
            end

            total_passed = 0
            total_failed = 0
            total_errors = 0
            total_known_failed = 0
            total_known_fixed = 0
            all_failures = []
            all_known_failures = []
            all_known_fixed = []
            max_failures = options[:max_failures]
            results_by_complexity = Hash.new { |h, k| h[k] = { pass: 0, fail: 0, error: 0 } }

            # Open log file for appending results
            log_file = File.open(results_log_path, "a")

            suites_to_run.each do |suite|

              suite_specs = Liquid::Spec::SpecLoader.load_suite(suite)
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
              known_failed = 0
              known_fixed = 0

              suite_specs.each do |spec|
                complexity = spec.complexity || 1000
                is_known = known_failures.known_failure?(spec.name)

                begin
                  result = run_single_spec(spec, config)
                rescue SystemExit, Interrupt, SignalException
                  raise
                rescue Exception => e
                  result = { status: :error, error: e }
                end

                case result[:status]
                when :pass
                  if is_known
                    # Known failure passed - might be fixed!
                    known_fixed += 1
                    all_known_fixed << { spec: spec, result: result }
                  end
                  passed += 1
                  results_by_complexity[complexity][:pass] += 1
                  log_result(log_file, run_id, spec, :success)
                when :fail
                  if is_known
                    known_failed += 1
                    all_known_failures << { spec: spec, result: result }
                    log_result(log_file, run_id, spec, :known_fail)
                  else
                    failed += 1
                    all_failures << { spec: spec, result: result }
                    log_result(log_file, run_id, spec, :fail)
                  end
                  results_by_complexity[complexity][:fail] += 1
                when :error
                  if is_known
                    known_failed += 1
                    all_known_failures << { spec: spec, result: result }
                    log_result(log_file, run_id, spec, :known_error)
                  else
                    errors += 1
                    all_failures << { spec: spec, result: result }
                    log_result(log_file, run_id, spec, :error)
                  end
                  results_by_complexity[complexity][:error] += 1
                end
              end

              parts = ["#{passed}/#{suite_specs.size} passed"]
              parts << "#{failed} failed" if failed > 0
              parts << "#{errors} errors" if errors > 0
              parts << "#{known_failed} known" if known_failed > 0
              puts parts.join(", ")

              total_passed += passed
              total_failed += failed
              total_errors += errors
              total_known_failed += known_failed
              total_known_fixed += known_fixed
            end

            log_file.close

            # Run additional specs if provided
            add_passed, add_failed, add_errors, add_known_failed, add_known_fixed =
              run_additional_specs(options, config, features, known_failures, all_failures, all_known_failures, all_known_fixed)
            total_passed += add_passed
            total_failed += add_failed
            total_errors += add_errors
            total_known_failed += add_known_failed
            total_known_fixed += add_known_fixed

            # Show skipped suites
            show_skipped_suites(config, features)

            # Print unexpected failures
            print_failures(all_failures, max_failures)

            # Print known failures (expected)
            print_known_failures(all_known_failures) if all_known_failures.any?

            # Print warnings about known failures that now pass
            print_known_fixed(all_known_fixed) if all_known_fixed.any?

            # Calculate max complexity reached (highest level where all specs pass)
            sorted_complexities = results_by_complexity.keys.sort
            max_complexity_reached = 0
            sorted_complexities.each do |c|
              r = results_by_complexity[c]
              if r[:fail] == 0 && r[:error] == 0
                max_complexity_reached = c
              else
                break
              end
            end
            max_possible = sorted_complexities.max || 0

            puts ""
            parts = ["#{total_passed} passed"]
            parts << "#{total_failed} failed" if total_failed > 0
            parts << "#{total_errors} errors" if total_errors > 0
            parts << "#{total_known_failed} known failures" if total_known_failed > 0
            parts << "#{total_known_fixed} known now passing" if total_known_fixed > 0
            puts "Total: #{parts.join(", ")}. Max complexity reached: #{max_complexity_reached}/#{max_possible}"

            # Determine exit code
            # - Unexpected failures always cause exit(1)
            # - Known failures that now pass cause exit(1) (stale entries should be removed)
            has_unexpected = all_failures.any?
            has_stale_known = all_known_fixed.any?

            exit(1) if has_unexpected || has_stale_known
          end

          def run_specs_compare(config, options)
            LiquidSpec.run_setup!
            require "liquid/spec"
            require "liquid/spec/deps/liquid_ruby"

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

            suites_to_run = determine_suites(config, features)

            total_same = 0
            total_different = 0
            total_errors = 0
            all_differences = []
            max_failures = options[:max_failures]

            suites_to_run.each do |suite|
              suite_specs = Liquid::Spec::SpecLoader.load_suite(suite)
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

            print_differences(all_differences, max_failures) if all_differences.any?

            puts ""

            if total_different == 0 && total_errors == 0
              puts "\e[32mTotal: #{total_same} specs match reference implementation\e[0m"
            else
              puts "Total: #{total_same} match, \e[33m#{total_different} different\e[0m, #{total_errors} errors"
            end

            exit(1) if all_differences.any?
          end

          private

          def run_benchmark_suites(suites, config, options)
            features = config.features
            profile_dir = nil

            if options[:profile]
              require "stackprof"
              profile_dir = "/tmp/liquid-spec-profile-#{Time.now.strftime("%Y%m%d_%H%M%S")}"
              Dir.mkdir(profile_dir)
              puts "Profiling enabled, output: #{profile_dir}"
              puts ""
            end

            suites.each do |suite|
              suite_specs = Liquid::Spec::SpecLoader.load_suite(suite)
              suite_specs = filter_specs(suite_specs, config.filter) if config.filter
              suite_specs = filter_by_features(suite_specs, features)

              next if suite_specs.empty?

              puts "Benchmark: #{suite.name}"
              puts "Duration: #{suite.default_iteration_seconds}s per spec"
              puts ""

              results = []

              # Prepare all specs first
              prepared_specs = suite_specs.map do |spec|
                prepare_benchmark_spec(spec, config)
              end.compact

              # Profile compile phase (all specs together)
              if profile_dir && prepared_specs.any?
                puts "  Profiling compile phase..."
                compile_profile = StackProf.run(mode: :cpu, raw: true) do
                  prepared_specs.each do |prepared|
                    100.times { LiquidSpec.do_compile(prepared[:template], prepared[:compile_options]) }
                  end
                end
                File.binwrite("#{profile_dir}/compile_cpu.dump", Marshal.dump(compile_profile))

                compile_obj_profile = StackProf.run(mode: :object, raw: true) do
                  prepared_specs.each do |prepared|
                    10.times { LiquidSpec.do_compile(prepared[:template], prepared[:compile_options]) }
                  end
                end
                File.binwrite("#{profile_dir}/compile_object.dump", Marshal.dump(compile_obj_profile))
              end

              # Profile render phase (all specs together)
              if profile_dir && prepared_specs.any?
                puts "  Profiling render phase..."
                render_profile = StackProf.run(mode: :cpu, raw: true) do
                  prepared_specs.each do |prepared|
                    100.times { LiquidSpec.do_render(deep_copy(prepared[:assigns]), prepared[:render_options]) }
                  end
                end
                File.binwrite("#{profile_dir}/render_cpu.dump", Marshal.dump(render_profile))

                render_obj_profile = StackProf.run(mode: :object, raw: true) do
                  prepared_specs.each do |prepared|
                    10.times { LiquidSpec.do_render(deep_copy(prepared[:assigns]), prepared[:render_options]) }
                  end
                end
                File.binwrite("#{profile_dir}/render_object.dump", Marshal.dump(render_obj_profile))
                puts ""
              end

              suite_specs.each do |spec|
                result = run_benchmark_spec(spec, config, suite.default_iteration_seconds)
                results << result

                # Print progress in hyperfine style
                if result[:error]
                  puts "  \e[31m✗\e[0m #{spec.name}"
                  puts "    Error: #{result[:error].message}"
                else
                  compile_ms = result[:compile_mean] * 1000
                  render_ms = result[:render_mean] * 1000
                  total_ms = compile_ms + render_ms
                  total_allocs = (result[:compile_allocs] || 0) + (result[:render_allocs] || 0)

                  puts "  \e[32m✓\e[0m #{spec.name}"
                  puts "    Compile: #{format_time(compile_ms)} ± #{format_time(result[:compile_stddev] * 1000)}    \e[2m(#{format_time(result[:compile_min] * 1000)} … #{format_time(result[:compile_max] * 1000)})  #{result[:compile_allocs]} allocs\e[0m"
                  puts "    Render:  #{format_time(render_ms)} ± #{format_time(result[:render_stddev] * 1000)}    \e[2m(#{format_time(result[:render_min] * 1000)} … #{format_time(result[:render_max] * 1000)})  #{result[:render_allocs]} allocs\e[0m"
                  puts "    Total:   #{format_time(total_ms)}    \e[2m#{result[:iterations]} runs, #{total_allocs} allocs\e[0m"
                end
                puts ""
              end

              print_benchmark_summary(results)
            end

            if profile_dir
              puts ""
              puts "=" * 60
              puts "StackProf profiles saved to: #{profile_dir}"
              puts "  #{profile_dir}/compile_cpu.dump"
              puts "  #{profile_dir}/compile_object.dump"
              puts "  #{profile_dir}/render_cpu.dump"
              puts "  #{profile_dir}/render_object.dump"
              puts ""
              puts "View with: stackprof #{profile_dir}/render_cpu.dump"
              puts "=" * 60
            end
          end

          def prepare_benchmark_spec(spec, _config)
            filesystem = spec.instantiate_filesystem
            compile_options = {
              line_numbers: true,
              error_mode: :strict,
              file_system: filesystem,
              template_name: spec.template_name,
            }.compact

            # Pre-compile to set up ctx[:template]
            LiquidSpec.do_compile(spec.template, compile_options)
            assigns = deep_copy(spec.instantiate_environment)
            render_options = {
              registers: build_registers(spec, filesystem),
              strict_errors: false,
            }.compact

            # Verify it works
            actual = LiquidSpec.do_render(deep_copy(assigns), render_options)
            return nil if spec.expected && actual != spec.expected

            {
              spec: spec,
              template: spec.template,
              compile_options: compile_options,
              assigns: assigns,
              render_options: render_options,
            }
          rescue
            nil
          end

          def run_benchmark_spec(spec, _config, duration_seconds)
            # Pre-compile the template
            filesystem = spec.instantiate_filesystem
            compile_options = {
              line_numbers: true,
              error_mode: :strict,
              file_system: filesystem,
              template_name: spec.template_name,
            }.compact

            LiquidSpec.do_compile(spec.template, compile_options)
            assigns = deep_copy(spec.instantiate_environment)
            render_options = {
              registers: build_registers(spec, filesystem),
              strict_errors: false,
            }.compact

            # Verify expected output first (warm up + validation)
            actual = LiquidSpec.do_render(deep_copy(assigns), render_options)
            if spec.expected && actual != spec.expected
              return {
                name: spec.name,
                iterations: 0,
                error: RuntimeError.new("Output mismatch:\n  Expected: #{spec.expected.inspect[0..100]}\n  Got: #{actual.inspect[0..100]}"),
              }
            end

            # Warm up
            3.times do
              LiquidSpec.do_compile(spec.template, compile_options)
              LiquidSpec.do_render(deep_copy(assigns), render_options)
            end

            # Count allocations for a single compile+render cycle
            GC.start
            alloc_before = GC.stat(:total_allocated_objects)
            LiquidSpec.do_compile(spec.template, compile_options)
            compile_allocs = GC.stat(:total_allocated_objects) - alloc_before

            alloc_before = GC.stat(:total_allocated_objects)
            LiquidSpec.do_render(deep_copy(assigns), render_options)
            render_allocs = GC.stat(:total_allocated_objects) - alloc_before

            # Disable GC for consistent timing
            GC.disable

            # Benchmark compile (half the duration)
            compile_times = benchmark_operation(duration_seconds / 2.0) do
              LiquidSpec.do_compile(spec.template, compile_options)
            end

            # Benchmark render (half the duration)
            render_times = benchmark_operation(duration_seconds / 2.0) do
              LiquidSpec.do_render(deep_copy(assigns), render_options)
            end

            # Re-enable GC
            GC.enable

            {
              name: spec.name,
              iterations: compile_times[:iterations] + render_times[:iterations],
              compile_mean: compile_times[:mean],
              compile_stddev: compile_times[:stddev],
              compile_min: compile_times[:min],
              compile_max: compile_times[:max],
              compile_allocs: compile_allocs,
              render_mean: render_times[:mean],
              render_stddev: render_times[:stddev],
              render_min: render_times[:min],
              render_max: render_times[:max],
              render_allocs: render_allocs,
              # Legacy fields for compatibility
              mean_time: render_times[:mean],
              stddev: render_times[:stddev],
              min_time: render_times[:min],
              max_time: render_times[:max],
              error: nil,
            }
          rescue => e
            # Ensure GC is re-enabled on error
            GC.enable
            {
              name: spec.name,
              iterations: 0,
              error: e,
            }
          end

          def benchmark_operation(duration_seconds)
            times = []
            max_iterations = 5000
            iterations = 0

            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end_time = start_time + duration_seconds

            # Initial timing to determine batch size
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            yield
            single_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

            # Target ~50ms per batch
            batch_size = [(0.05 / [single_time, 0.0001].max).to_i, 1].max
            batch_size = [batch_size, 500].min

            while iterations < max_iterations && Process.clock_gettime(Process::CLOCK_MONOTONIC) < end_time
              batch_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              batch_size.times { yield }
              batch_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - batch_start
              times << batch_elapsed / batch_size
              iterations += batch_size
            end

            mean = times.sum / times.size
            variance = times.map { |t| (t - mean) ** 2 }.sum / times.size

            {
              mean: mean,
              stddev: Math.sqrt(variance),
              min: times.min,
              max: times.max,
              iterations: iterations,
            }
          end

          def format_number(num)
            return "0" if num.zero?

            if num >= 1_000_000
              "%.2fM" % (num / 1_000_000.0)
            elsif num >= 1_000
              "%.2fk" % (num / 1_000.0)
            else
              "%.2f" % num
            end
          end

          def format_time(ms)
            if ms >= 1000
              "%.3f s" % (ms / 1000.0)
            elsif ms >= 1
              "%.3f ms" % ms
            else
              "%.3f µs" % (ms * 1000)
            end
          end

          def print_benchmark_summary(results)
            # No summary for single-adapter benchmarks - each benchmark measures
            # a different template, so comparing them doesn't make sense.
            # Comparisons are only meaningful in matrix mode where we compare
            # the same benchmark across different implementations.
          end

          def determine_suites(config, features)
            specific_suite = config.suite != :all ? Liquid::Spec::Suite.find(config.suite) : nil

            if specific_suite
              [specific_suite]
            else
              Liquid::Spec::Suite.defaults
                .select { |s| s.runnable_with?(features) }
                .sort_by { |s| s.id == :basics ? "" : s.id.to_s }
            end
          end

          def run_additional_specs(options, config, features, known_failures, all_failures, all_known_failures, all_known_fixed)
            return [0, 0, 0, 0, 0] if options[:add_specs].nil? || options[:add_specs].empty?

            additional_specs = load_additional_specs(options[:add_specs])
            additional_specs = filter_specs(additional_specs, config.filter) if config.filter
            additional_specs = filter_by_features(additional_specs, features)
            additional_specs = sort_by_complexity(additional_specs)

            return [0, 0, 0, 0, 0] if additional_specs.empty?

            suite_name_padded = "Additional Specs ".ljust(40, ".")
            print("#{suite_name_padded} ")
            $stdout.flush

            passed = 0
            failed = 0
            errors = 0
            known_failed = 0
            known_fixed = 0

            additional_specs.each do |spec|
              is_known = known_failures.known_failure?(spec.name)

              begin
                result = run_single_spec(spec, config)
              rescue SystemExit, Interrupt, SignalException
                raise
              rescue Exception => e
                result = { status: :error, error: e }
              end

              case result[:status]
              when :pass
                if is_known
                  known_fixed += 1
                  all_known_fixed << { spec: spec, result: result }
                end
                passed += 1
              when :fail
                if is_known
                  known_failed += 1
                  all_known_failures << { spec: spec, result: result }
                else
                  failed += 1
                  all_failures << { spec: spec, result: result }
                end
              when :error
                if is_known
                  known_failed += 1
                  all_known_failures << { spec: spec, result: result }
                else
                  errors += 1
                  all_failures << { spec: spec, result: result }
                end
              end
            end

            parts = ["#{passed}/#{additional_specs.size} passed"]
            parts << "#{failed} failed" if failed > 0
            parts << "#{errors} errors" if errors > 0
            parts << "#{known_failed} known" if known_failed > 0
            puts parts.join(", ")

            [passed, failed, errors, known_failed, known_fixed]
          end

          def show_skipped_suites(config, features)
            skipped = Liquid::Spec::Suite.defaults.select { |s| !s.runnable_with?(features) }
            skipped.each do |suite|
              missing = suite.missing_features(features)
              suite_name_padded = "#{suite.name} ".ljust(40, ".")
              puts "#{suite_name_padded} skipped (needs #{missing.join(", ")})"
            end
          end

          def print_labeled_value(label, value)
            padding = " " * (11 - label.length)
            value_str = value.to_s
            if value_str.include?("\n")
              # Multi-line: show on next line with indentation
              indented = value_str.gsub("\n", "\n              ")
              puts "   #{label}:#{padding}\n              #{indented}"
            else
              puts "   #{label}:#{padding}#{value_str.inspect}"
            end
          end

          def print_failures(failures, max_failures = nil)
            return if failures.empty?

            puts ""
            puts "Failures:"
            puts ""

            shown_hints = Set.new

            # Determine how many to print
            print_count = max_failures ? [failures.size, max_failures].min : failures.size

            failures.first(print_count).each_with_index do |f, i|
              spec = f[:spec]
              result = f[:result]

              # Show location first
              location = spec.source_file
              location = "#{location}:#{spec.line_number}" if spec.line_number
              puts "\e[2m#{location}\e[0m"

              puts "#{i + 1}) #{spec.name}"
              print_labeled_value("Template", spec.template)

              # Show environment if present
              if spec.raw_environment.is_a?(Hash) && !spec.raw_environment.empty?
                print_labeled_value("Environment", spec.raw_environment.inspect)
              elsif spec.raw_environment.is_a?(String) && !spec.raw_environment.empty?
                print_labeled_value("Environment", spec.raw_environment)
              end

              # Show filesystem if present
              if spec.raw_filesystem.is_a?(Hash) && !spec.raw_filesystem.empty?
                files_summary = spec.raw_filesystem.keys.join(", ")
                files_summary = files_summary[0..77] + "..." if files_summary.length > 80
                puts "   Filesystem: #{files_summary}"
              end

              print_labeled_value("Expected", result[:expected])
              print_labeled_value("Got", result[:actual])
              if result[:error]
                puts "   Error:    #{result[:error].class}: #{result[:error].message}"
              end

              effective_hint = spec.effective_hint
              if effective_hint && !shown_hints.include?(effective_hint)
                shown_hints << effective_hint
                puts ""
                puts "   Hint: #{effective_hint.strip.gsub("\n", "\n         ")}"
              end

              puts ""
            end

            # Show truncation message if we limited output
            if max_failures && failures.size > max_failures
              puts "\e[2m(... #{failures.size - max_failures} more failures not shown due to --max-failures #{max_failures} ...)\e[0m"
              puts ""
            end
          end

          def print_known_failures(known_failures)
            return if known_failures.empty?

            puts ""
            puts "\e[33mKnown failures (expected):\e[0m"

            known_failures.each_with_index do |f, i|
              puts "  #{i + 1}) #{f[:spec].name}"
            end

            puts ""
          end

          def print_known_fixed(known_fixed)
            return if known_fixed.empty?

            puts ""
            puts "\e[31mKnown failures that now PASS:\e[0m"

            known_fixed.each_with_index do |f, i|
              puts "  #{i + 1}) #{f[:spec].name}"
            end

            puts ""
            puts "\e[31mRemove these from your known_failures list to pass.\e[0m"
            puts ""
          end

          def print_differences(differences, max_failures = nil)
            puts ""
            puts "\e[33mDifferences from reference liquid-ruby:\e[0m"
            puts ""

            # Determine how many to print
            print_count = max_failures ? [differences.size, max_failures].min : differences.size

            differences.first(print_count).each_with_index do |d, i|
              puts "#{i + 1}) #{d[:spec].name}"
              print_labeled_value("Template", d[:spec].template)
              if d[:result][:reference_error]
                puts "   Reference: \e[31mERROR\e[0m #{d[:result][:reference_error].class}: #{d[:result][:reference_error].message}"
              else
                print_labeled_value("Reference", d[:result][:reference])
              end
              if d[:result][:adapter_error]
                puts "   Adapter:   \e[31mERROR\e[0m #{d[:result][:adapter_error].class}: #{d[:result][:adapter_error].message}"
              else
                print_labeled_value("Adapter", d[:result][:adapter])
              end
              hint = d[:spec].effective_hint
              if hint
                puts "   Hint: #{hint.strip.gsub("\n", "\n         ")}"
              end
              puts ""
            end

            # Show truncation message if we limited output
            if max_failures && differences.size > max_failures
              puts "\e[2m(... #{differences.size - max_failures} more differences not shown due to --max-failures #{max_failures} ...)\e[0m"
              puts ""
            end

            puts ""
            puts "\e[1;33m#{"=" * 60}\e[0m"
            puts "\e[1;33m  #{differences.size} DIFFERENCES DETECTED\e[0m"
            puts "\e[1;33m#{"=" * 60}\e[0m"
            puts ""
            puts "Please contribute documented differences to liquid-spec:"
            puts "  \e[4mhttps://github.com/Shopify/liquid-spec\e[0m"
            puts ""
          end

          def compare_single_spec(spec, _config)
            required_opts = spec.source_required_options || {}
            render_errors = spec.render_errors || required_opts[:render_errors] || spec.expects_render_error?

            compile_options = {
              line_numbers: true,
              error_mode: spec.error_mode&.to_sym || required_opts[:error_mode],
              template_name: spec.template_name,
            }.compact

            assigns = deep_copy(spec.instantiate_environment)
            render_options = {
              registers: build_registers(spec),
              strict_errors: !render_errors,
            }.compact

            reference_result, reference_error = run_reference_spec(spec, compile_options, assigns, render_options)
            adapter_result, adapter_error = run_adapter_spec(spec, compile_options, assigns, render_options)

            if reference_error && adapter_error
              if reference_error.class == adapter_error.class
                { status: :same }
              else
                { status: :different, reference: nil, reference_error: reference_error, adapter: nil, adapter_error: adapter_error }
              end
            elsif reference_error
              { status: :different, reference: nil, reference_error: reference_error, adapter: adapter_result, adapter_error: nil }
            elsif adapter_error
              { status: :different, reference: reference_result, reference_error: nil, adapter: nil, adapter_error: adapter_error }
            elsif reference_result == adapter_result
              { status: :same }
            else
              { status: :different, reference: reference_result, reference_error: nil, adapter: adapter_result, adapter_error: nil }
            end
          rescue StandardError => e
            { status: :error, error: e }
          end

          def run_reference_spec(spec, _compile_options, assigns, render_options)
            strict_compile_options = { line_numbers: true, error_mode: :strict }
            template = Liquid::Template.parse(spec.template, **strict_compile_options)

            context = Liquid::Context.build(
              static_environments: assigns,
              registers: Liquid::Registers.new(render_options[:registers] || {}),
              rethrow_errors: true,
            )

            ref_result = template.render(context)
            [ref_result, nil]
          rescue SystemExit, Interrupt, SignalException
            raise
          rescue Exception => e
            [nil, e]
          end

          def run_adapter_spec(spec, compile_options, assigns, render_options)
            LiquidSpec.do_compile(spec.template, compile_options)
            adapter_result = LiquidSpec.do_render(assigns, render_options)
            [adapter_result, nil]
          rescue SystemExit, Interrupt, SignalException
            raise
          rescue Exception => e
            [nil, e]
          end

          def run_single_spec(spec, _config)
            required_opts = spec.source_required_options || {}
            render_errors = spec.render_errors || required_opts[:render_errors] || spec.expects_render_error?

            # Build filesystem first so it can be passed to compile
            filesystem = spec.instantiate_filesystem

            compile_options = {
              line_numbers: true,
              error_mode: spec.error_mode&.to_sym || required_opts[:error_mode],
              file_system: filesystem,
              template_name: spec.template_name,
            }.compact

            begin
              LiquidSpec.do_compile(spec.template, compile_options)
            rescue => e
              # Check if error class name contains "SyntaxError" (parse error)
              if e.class.name.include?("SyntaxError")
                if spec.expects_parse_error?
                  return check_error_patterns(e, spec.error_patterns(:parse_error), "parse_error")
                end
                if render_errors
                  return compare_result(e.message, spec.expected)
                else
                  raise
                end
              else
                raise
              end
            end

            if spec.expects_parse_error?
              return {
                status: :fail,
                expected: "parse_error matching #{spec.error_patterns(:parse_error).map(&:inspect).join(", ")}",
                actual: "no error (template parsed successfully)",
              }
            end

            assigns = deep_copy(spec.instantiate_environment)
            render_options = {
              registers: build_registers(spec, filesystem),
              strict_errors: !render_errors,
            }.compact

            begin
              actual = LiquidSpec.do_render(assigns, render_options)
            rescue StandardError => e
              if spec.expects_render_error?
                return check_error_patterns(e, spec.error_patterns(:render_error), "render_error")
              end

              raise
            end

            if spec.expects_render_error?
              return {
                status: :fail,
                expected: "render_error matching #{spec.error_patterns(:render_error).map(&:inspect).join(", ")}",
                actual: "no error (rendered: #{actual.inspect})",
              }
            end

            if spec.expects_output_patterns?
              return check_output_patterns(actual, spec.error_patterns(:output))
            end

            compare_result(actual, spec.expected)
          rescue StandardError => e
            { status: :error, expected: spec.expected, actual: nil, error: e }
          end

          # Extract core message from Liquid error formats:
          #   "Liquid::ArgumentError (templates/foo line 1): invalid integer"
          #   "Liquid::SyntaxError (line 5): unexpected token"
          #   "Liquid::Error: something went wrong"
          # Returns just "invalid integer", "unexpected token", etc.
          def extract_core_message(text)
            if text =~ /\):\s*(.+)$/m
              $1.strip
            elsif text =~ /:\s*(.+)$/m
              $1.strip
            else
              text
            end
          end

          def check_error_patterns(error, patterns, error_type)
            message = error.message
            core_message = extract_core_message(message)
            # Match against both full message and core message for flexibility
            failed_patterns = patterns.reject { |pattern| pattern.match?(message) || pattern.match?(core_message) }

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

          def check_output_patterns(output, patterns)
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

          def compare_result(actual, expected)
            if actual == expected
              { status: :pass }
            else
              { status: :fail, expected: expected, actual: actual }
            end
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

          def load_specs(config)
            LiquidSpec.run_setup!
            require "liquid/spec"

            suite_id = config.suite
            features = config.features

            case suite_id
            when :all
              Liquid::Spec::Suite.defaults
                .select { |s| s.runnable_with?(features) }
                .flat_map { |s| Liquid::Spec::SpecLoader.load_suite(s) }
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
                exit(1)
              end

              Liquid::Spec::SpecLoader.load_suite(suite)
            end
          end

          def filter_specs(specs, pattern)
            specs.select { |s| s.name =~ pattern }
          end

          def load_additional_specs(globs)
            specs = []
            globs.each do |glob|
              Dir[glob].each do |path|
                file_specs = Liquid::Spec::SpecLoader.load_file(path)
                specs.concat(file_specs)
              rescue => e
                $stderr.puts "Warning: Could not load #{path}: #{e.message}"
              end
            end
            specs
          end

          def filter_by_features(specs, features)
            feature_set = Set.new(features.map(&:to_sym))
            specs.select { |s| s.runnable_with?(feature_set) }
          end

          def parse_filter_pattern(pattern)
            if pattern =~ %r{\A/(.+)/([imx]*)\z}
              regex_str = ::Regexp.last_match(1)
              flags = ::Regexp.last_match(2)
              options = 0
              options |= Regexp::IGNORECASE if flags.include?("i")
              options |= Regexp::MULTILINE if flags.include?("m")
              options |= Regexp::EXTENDED if flags.include?("x")
              Regexp.new(regex_str, options)
            else
              Regexp.new(pattern, Regexp::IGNORECASE)
            end
          end

          def filter_strict_only(specs)
            specs.select do |s|
              mode = s.error_mode&.to_sym
              mode.nil? || mode == :strict
            end
          end

          def sort_by_complexity(specs)
            specs.sort_by { |s| s.complexity || Float::INFINITY }
          end

          def results_log_path
            File.join(RESULTS_LOG_DIR, "liquid-spec-results.jsonl")
          end

          def log_result(log_file, run_id, spec, status)
            return unless log_file

            entry = [
              run_id,
              Liquid::Spec::VERSION,
              spec.source_file,
              spec.name,
              spec.complexity || 1000,
              status.to_s,
            ]
            log_file.puts(JSON.generate(entry))
          end
        end
      end
    end
  end
end
