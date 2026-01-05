# frozen_string_literal: true

module Liquid
  module Spec
    module CLI
      # Matrix command - run specs across multiple adapters and compare results
      module Matrix
        HELP = <<~HELP
          Usage: liquid-spec matrix [options]

          Run specs across multiple adapters and compare results.
          Shows differences between implementations.

          Options:
            --all                 Run all available adapters from examples/
            --adapters=LIST       Comma-separated list of adapters to run
            --reference=NAME      Reference adapter (default: liquid_ruby)
            -n, --name PATTERN    Filter specs by name pattern
            -s, --suite SUITE     Spec suite: all, basics, liquid_ruby, etc.
            -b, --bench           Run timing suites as benchmarks, compare across adapters
            --max-failures N      Stop after N differences (default: 10)
            --no-max-failures     Show all differences (not recommended)
            -v, --verbose         Show detailed output
            -h, --help            Show this help

          Examples:
            liquid-spec matrix --all
            liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax
            liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax -n truncate
            liquid-spec matrix --adapters=liquid_ruby,liquid_c -s benchmarks --bench

        HELP

        class << self
          def run(args)
            if args.include?("-h") || args.include?("--help")
              puts HELP
              return
            end

            options = parse_options(args)
            run_matrix(options)
          end

          private

          def parse_options(args)
            options = {
              all: false,
              adapters: [],
              reference: "liquid_ruby",
              filter: nil,
              suite: :all,
              max_failures: 10,
              verbose: false,
              bench: false,
            }

            while args.any?
              arg = args.shift
              case arg
              when "--all"
                options[:all] = true
              when /\A--adapters=(.+)\z/
                options[:adapters] = ::Regexp.last_match(1).split(",").map(&:strip)
              when "--reference"
                options[:reference] = args.shift
              when /\A--reference=(.+)\z/
                options[:reference] = ::Regexp.last_match(1)
              when "-n", "--name"
                options[:filter] = args.shift
              when /\A--name=(.+)\z/, /\A-n(.+)\z/
                options[:filter] = ::Regexp.last_match(1)
              when "-s", "--suite"
                options[:suite] = args.shift.to_sym
              when /\A--suite=(.+)\z/
                options[:suite] = ::Regexp.last_match(1).to_sym
              when "-b", "--bench"
                options[:bench] = true
              when "--max-failures"
                options[:max_failures] = args.shift.to_i
              when /\A--max-failures=(\d+)\z/
                options[:max_failures] = ::Regexp.last_match(1).to_i
              when "--no-max-failures"
                options[:max_failures] = nil
              when "-v", "--verbose"
                options[:verbose] = true
              end
            end

            options
          end

          def run_matrix(options)
            # Discover all adapters if --all specified
            if options[:all]
              options[:adapters] = discover_all_adapters
            end

            if options[:adapters].empty?
              $stderr.puts "Error: Specify --all or --adapters=LIST"
              $stderr.puts "Example: liquid-spec matrix --all"
              $stderr.puts "Example: liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax"
              exit(1)
            end

            # Load liquid first, then spec infrastructure
            require "liquid"
            require "liquid/spec"
            require "liquid/spec/deps/liquid_ruby"

            # Load adapters
            puts "Loading adapters..."
            adapters = load_adapters(options[:adapters])

            if adapters.empty?
              $stderr.puts "Error: No adapters loaded"
              exit(1)
            end

            puts "Loaded #{adapters.size} adapter(s): #{adapters.keys.join(", ")}"

            # Dispatch to benchmark mode if --bench
            if options[:bench]
              run_benchmarks(adapters, options)
              return
            end

            # Load specs for comparison mode
            puts "Loading specs..."
            specs = Liquid::Spec::SpecLoader.load_all(
              suite: options[:suite],
              filter: options[:filter],
            )

            if specs.empty?
              puts "No specs to run"
              return
            end

            puts "Loaded #{specs.size} specs"
            puts

            # Verify reference adapter exists
            reference_name = options[:reference]
            unless adapters.key?(reference_name)
              $stderr.puts "Error: Reference adapter '#{reference_name}' not found"
              $stderr.puts "Available: #{adapters.keys.join(", ")}"
              exit(1)
            end

            puts "Reference: #{reference_name}"
            puts

            # Run comparison
            run_comparison(specs, adapters, reference_name, options)
          end

          def discover_all_adapters
            gem_root = File.expand_path("../../../../..", __FILE__)
            examples_dir = File.join(gem_root, "examples")

            adapters = Dir[File.join(examples_dir, "*.rb")].map do |path|
              File.basename(path, ".rb")
            end.sort

            # Ensure liquid_ruby is first (reference)
            if adapters.include?("liquid_ruby")
              adapters.delete("liquid_ruby")
              adapters.unshift("liquid_ruby")
            end

            adapters
          end

          def load_adapters(adapter_names)
            gem_root = File.expand_path("../../../../..", __FILE__)
            examples_dir = File.join(gem_root, "examples")

            adapters = {}
            adapter_names.each do |name|
              # Support both short names (from examples/) and full paths
              if File.exist?(name)
                path = name
                adapter_name = File.basename(name, ".rb")
              elsif File.exist?(name + ".rb")
                path = name + ".rb"
                adapter_name = File.basename(name)
              else
                path = File.join(examples_dir, "#{name}.rb")
                adapter_name = name
              end

              unless File.exist?(path)
                $stderr.puts "Warning: Adapter not found: #{name}"
                next
              end

              begin
                # Reset LiquidSpec state before loading each adapter
                reset_liquid_spec!

                adapter = Liquid::Spec::AdapterRunner.new(name: adapter_name)
                adapter.load_dsl(path)
                adapter.ensure_setup!
                adapters[adapter_name] = adapter
              rescue LiquidSpec::SkipAdapter => e
                $stderr.puts "Skipping #{adapter_name}: #{e.message}"
              rescue => e
                $stderr.puts "Warning: Failed to load #{adapter_name}: #{e.message}"
              end
            end

            adapters
          end

          def reset_liquid_spec!
            return unless defined?(::LiquidSpec)

            # Reset the module state
            ::LiquidSpec.instance_variable_set(:@setup_block, nil)
            ::LiquidSpec.instance_variable_set(:@compile_block, nil)
            ::LiquidSpec.instance_variable_set(:@render_block, nil)
            ::LiquidSpec.instance_variable_set(:@config, nil)
          end

          def run_comparison(specs, adapters, reference_name, options)
            differences = []
            matched = 0
            skipped = 0
            checked = 0

            max_failures = options[:max_failures]
            verbose = options[:verbose]

            print("Running #{specs.size} specs: ")
            $stdout.flush

            specs.each do |spec|
              # Run on ALL adapters that can run this spec
              outputs = {}
              adapters.each do |name, adapter|
                begin
                  result = adapter.run_single(spec)
                rescue SystemExit, Interrupt, SignalException
                  raise
                rescue Exception => e
                  result = Liquid::Spec::SpecResult.new(
                    spec: spec,
                    status: :error,
                    output: "#{e.class}: #{e.message}",
                  )
                end

                outputs[name] = if result.skipped?
                  { skipped: true }
                else
                  { output: normalize_output(result) }
                end
              end

              # Check if any adapter actually ran this spec
              ran_outputs = outputs.reject { |_, v| v[:skipped] }
              if ran_outputs.empty?
                skipped += 1
                print("s") if verbose
                next
              end

              checked += 1

              # Check if all outputs match
              unique_outputs = ran_outputs.values.map { |v| v[:output] }.uniq
              if unique_outputs.size == 1
                matched += 1
                print(".") if verbose
              else
                # Build diff info - group adapters by their output
                first_output = ran_outputs.values.first[:output]
                differences << {
                  spec: spec,
                  outputs: outputs,
                  first_output: first_output,
                }
                print("F") if verbose

                if max_failures && differences.size >= max_failures
                  puts " (stopped at max-failures)"
                  break
                end
              end
            end

            puts " done" unless verbose
            puts

            # Print results
            print_results_v2(differences, adapters, options)
            print_summary(matched, differences.size, skipped, checked, specs.size, adapters)

            exit(1) if differences.any?
          end

          def run_benchmarks(adapters, options)
            # Find timing suites
            timing_suites = Liquid::Spec::Suite.all.select(&:timings?)

            if options[:suite] != :all
              timing_suites = timing_suites.select { |s| s.id == options[:suite] }
            end

            if timing_suites.empty?
              $stderr.puts "Error: No timing suites found"
              $stderr.puts "Use -s benchmarks or run against a suite with timings: true"
              exit(1)
            end

            puts ""

            # Collect all results across suites
            all_results = []

            timing_suites.each do |suite|
              specs = Liquid::Spec::SpecLoader.load_suite(suite)
              specs = filter_specs_by_pattern(specs, options[:filter]) if options[:filter]

              next if specs.empty?

              puts "=" * 70
              puts "Benchmark: #{suite.name}"
              puts "Duration: #{suite.default_iteration_seconds}s per spec"
              puts "=" * 70
              puts ""

              specs.each do |spec|
                results = run_benchmark_comparison(spec, adapters, suite.default_iteration_seconds)
                all_results << { spec: spec, results: results }
              end
            end

            # Print summary at end
            print_benchmark_summaries(all_results, adapters)
          end

          def run_benchmark_comparison(spec, adapters, duration_seconds)
            puts "\e[1m#{spec.name}\e[0m"

            # Collect results from all adapters
            results = {}

            adapters.each do |name, adapter|
              next unless adapter.can_run?(spec)

              result = run_single_benchmark(spec, adapter, duration_seconds)
              results[name] = result

              if result[:error]
                puts "  \e[31m✗\e[0m #{name}: #{result[:error].message[0..60]}"
              else
                compile_ms = result[:compile_mean] * 1000
                render_ms = result[:render_mean] * 1000
                total_ms = compile_ms + render_ms

                puts "  \e[32m✓\e[0m #{name}"
                puts "      Compile: #{format_time(compile_ms)} ± #{format_time(result[:compile_stddev] * 1000)}"
                puts "      Render:  #{format_time(render_ms)} ± #{format_time(result[:render_stddev] * 1000)}"
                puts "      Total:   #{format_time(total_ms)}"
              end
            end

            puts ""
            results
          end

          def run_single_benchmark(spec, adapter, duration_seconds)
            # Prepare spec data
            environment = spec.instantiate_environment
            filesystem = spec.instantiate_filesystem
            template_factory = spec.instantiate_template_factory

            compile_options = { line_numbers: true }
            compile_options[:error_mode] = spec.error_mode if spec.error_mode
            compile_options[:file_system] = filesystem if filesystem

            registers = {}
            registers[:file_system] = filesystem if filesystem
            registers[:template_factory] = template_factory if template_factory

            render_options = {
              registers: registers,
              strict_errors: false,
            }
            render_options[:error_mode] = spec.error_mode if spec.error_mode

            # Verify it works first
            template = adapter.instance_variable_get(:@compile_block).call(spec.template, compile_options)
            actual = adapter.instance_variable_get(:@render_block).call(template, deep_copy(environment), render_options)

            if spec.expected && actual.to_s != spec.expected
              return {
                error: RuntimeError.new("Output mismatch: expected #{spec.expected.inspect[0..50]}, got #{actual.to_s.inspect[0..50]}"),
              }
            end

            # Warm up
            3.times do
              t = adapter.instance_variable_get(:@compile_block).call(spec.template, compile_options)
              adapter.instance_variable_get(:@render_block).call(t, deep_copy(environment), render_options)
            end

            # Benchmark compile
            compile_times = benchmark_operation(duration_seconds / 2.0) do
              adapter.instance_variable_get(:@compile_block).call(spec.template, compile_options)
            end

            # Benchmark render (pre-compiled template)
            render_times = benchmark_operation(duration_seconds / 2.0) do
              adapter.instance_variable_get(:@render_block).call(template, deep_copy(environment), render_options)
            end

            {
              compile_mean: mean(compile_times),
              compile_stddev: stddev(compile_times),
              compile_min: compile_times.min,
              compile_max: compile_times.max,
              compile_runs: compile_times.size,
              render_mean: mean(render_times),
              render_stddev: stddev(render_times),
              render_min: render_times.min,
              render_max: render_times.max,
              render_runs: render_times.size,
              error: nil,
            }
          rescue => e
            { error: e }
          end

          def benchmark_operation(duration_seconds, &block)
            times = []
            max_iterations = 5000
            iterations = 0

            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end_time = start_time + duration_seconds

            # Initial timing to determine batch size
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            block.call
            single_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

            # Target ~50ms per batch
            batch_size = [(0.05 / [single_time, 0.0001].max).to_i, 1].max
            batch_size = [batch_size, 500].min

            while iterations < max_iterations && Process.clock_gettime(Process::CLOCK_MONOTONIC) < end_time
              batch_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              batch_size.times { block.call }
              batch_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - batch_start
              times << batch_elapsed / batch_size
              iterations += batch_size
            end

            times
          end

          def print_benchmark_summaries(all_results, adapters)
            return if all_results.empty?

            # Only show comparison if multiple adapters
            adapter_names = adapters.keys
            return if adapter_names.size < 2

            puts ""
            puts "=" * 70
            puts "SUMMARY"
            puts "=" * 70

            # Per-benchmark summaries
            all_results.each do |entry|
              spec = entry[:spec]
              results = entry[:results]
              valid = results.reject { |_, r| r[:error] }
              next if valid.size < 2

              puts ""
              puts "\e[1m#{spec.name}\e[0m"
              print_single_benchmark_comparison(valid)
            end

            # Overall summary - aggregate across all benchmarks
            puts ""
            puts "-" * 70
            puts "\e[1mOverall\e[0m"

            # Compute geometric mean of ratios for each adapter pair
            # We use the first adapter as reference
            reference_name = adapter_names.first
            other_adapters = adapter_names[1..]

            compile_ratios = Hash.new { |h, k| h[k] = [] }
            render_ratios = Hash.new { |h, k| h[k] = [] }

            all_results.each do |entry|
              results = entry[:results]
              valid = results.reject { |_, r| r[:error] }

              next unless valid.key?(reference_name)
              ref = valid[reference_name]

              other_adapters.each do |name|
                next unless valid.key?(name)
                other = valid[name]

                compile_ratios[name] << other[:compile_mean] / ref[:compile_mean]
                render_ratios[name] << other[:render_mean] / ref[:render_mean]
              end
            end

            # Compute geometric means
            puts "  \e[1mCompile:\e[0m"
            compile_ratios.each do |name, ratios|
              next if ratios.empty?
              geomean = geometric_mean(ratios)
              if geomean > 1
                puts "    \e[36m#{reference_name}\e[0m ran \e[32m%.2fx\e[0m faster than \e[36m#{name}\e[0m (geometric mean)" % geomean
              else
                puts "    \e[36m#{name}\e[0m ran \e[32m%.2fx\e[0m faster than \e[36m#{reference_name}\e[0m (geometric mean)" % (1.0 / geomean)
              end
            end

            puts "  \e[1mRender:\e[0m"
            render_ratios.each do |name, ratios|
              next if ratios.empty?
              geomean = geometric_mean(ratios)
              if geomean > 1
                puts "    \e[36m#{reference_name}\e[0m ran \e[32m%.2fx\e[0m faster than \e[36m#{name}\e[0m (geometric mean)" % geomean
              else
                puts "    \e[36m#{name}\e[0m ran \e[32m%.2fx\e[0m faster than \e[36m#{reference_name}\e[0m (geometric mean)" % (1.0 / geomean)
              end
            end

            puts ""
          end

          def print_single_benchmark_comparison(valid)
            # Compile comparison
            compile_sorted = valid.sort_by { |_, r| r[:compile_mean] }
            fastest_compile_name, fastest_compile = compile_sorted.first

            puts "  \e[1mCompile:\e[0m \e[36m#{fastest_compile_name}\e[0m ran"
            compile_sorted[1..].each do |name, r|
              ratio = r[:compile_mean] / fastest_compile[:compile_mean]
              fastest_rel_err = fastest_compile[:compile_stddev] / fastest_compile[:compile_mean]
              result_rel_err = r[:compile_stddev] / r[:compile_mean]
              ratio_err = ratio * Math.sqrt(fastest_rel_err**2 + result_rel_err**2)
              puts "    \e[32m%.2f\e[0m ± \e[32m%.2f\e[0m times faster than \e[36m#{name}\e[0m" % [ratio, ratio_err]
            end

            # Render comparison
            render_sorted = valid.sort_by { |_, r| r[:render_mean] }
            fastest_render_name, fastest_render = render_sorted.first

            puts "  \e[1mRender:\e[0m \e[36m#{fastest_render_name}\e[0m ran"
            render_sorted[1..].each do |name, r|
              ratio = r[:render_mean] / fastest_render[:render_mean]
              fastest_rel_err = fastest_render[:render_stddev] / fastest_render[:render_mean]
              result_rel_err = r[:render_stddev] / r[:render_mean]
              ratio_err = ratio * Math.sqrt(fastest_rel_err**2 + result_rel_err**2)
              puts "    \e[32m%.2f\e[0m ± \e[32m%.2f\e[0m times faster than \e[36m#{name}\e[0m" % [ratio, ratio_err]
            end
          end

          def geometric_mean(arr)
            return 0 if arr.empty?
            (arr.reduce(1.0) { |prod, x| prod * x })**(1.0 / arr.size)
          end

          def filter_specs_by_pattern(specs, pattern)
            regex = if pattern =~ %r{\A/(.+)/([imx]*)\z}
              regex_str = ::Regexp.last_match(1)
              flags = ::Regexp.last_match(2)
              opts = 0
              opts |= Regexp::IGNORECASE if flags.include?("i")
              Regexp.new(regex_str, opts)
            else
              Regexp.new(pattern, Regexp::IGNORECASE)
            end
            specs.select { |s| s.name =~ regex }
          end

          def mean(arr)
            arr.sum / arr.size.to_f
          end

          def stddev(arr)
            m = mean(arr)
            variance = arr.map { |x| (x - m)**2 }.sum / arr.size.to_f
            Math.sqrt(variance)
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

          def normalize_output(result)
            if result.errored? || result.failed?
              # Normalize error output
              output = result.output.to_s
              # Remove line numbers for comparison
              output = output.gsub(/\(line \d+\)/, "(line N)")
              # Remove trailing context
              output = output.sub(/\s+in\s+"[^"]*"\s*\z/i, "")
              "ERROR:#{output.downcase}"
            else
              result.output.to_s
            end
          end

          def outputs_match?(output1, output2)
            return true if output1 == output2

            # Flexible error comparison
            if output1.start_with?("ERROR:") && output2.start_with?("ERROR:")
              msg1 = output1.sub(/\AERROR:/, "")
              msg2 = output2.sub(/\AERROR:/, "")
              return true if msg1 == msg2
              return true if msg1.include?(msg2) || msg2.include?(msg1)
            end

            false
          end

          def print_results_v2(differences, adapters, options)
            return if differences.empty?

            puts "=" * 70
            puts "DIFFERENCES"
            puts "=" * 70
            puts

            differences.each_with_index do |diff, idx|
              puts "-" * 70
              puts "\e[1m#{idx + 1}. #{diff[:spec].name}\e[0m"
              puts
              puts "\e[2mTemplate:\e[0m"
              template = diff[:spec].template
              if template.include?("\n")
                template.each_line { |l| puts "  #{l}" }
              else
                puts "  #{template}"
              end
              puts

              # Collect outputs, marking skipped adapters
              outputs = {}
              diff[:outputs].each do |name, data|
                outputs[name] = data[:skipped] ? "(skipped)" : data[:output]
              end

              # Group by output value
              by_output = outputs.group_by { |_, v| v }.transform_values { |pairs| pairs.map(&:first) }

              by_output.each do |output, names|
                puts "\e[2mAdapters:\e[0m #{names.join(", ")}"
                puts "\e[2mOutput:\e[0m"
                print_output(output)
                puts
              end
            end

            puts "=" * 70
            puts
          end

          def print_output(output)
            if output.nil?
              puts "  \e[2m(nil)\e[0m"
            elsif output.to_s.empty?
              puts "  \e[2m(empty string)\e[0m"
            elsif output == "(skipped)"
              puts "  \e[2m(skipped - adapter doesn't support)\e[0m"
            elsif output.to_s.include?("\n")
              output.to_s.each_line.with_index do |line, i|
                puts "  #{i + 1}: #{line.chomp.inspect}"
              end
            else
              puts "  #{output.inspect}"
            end
          end

          def print_summary(matched, diff_count, skipped, checked, total, adapters)
            puts "=" * 70
            puts "SUMMARY"
            puts "=" * 70
            puts

            if diff_count == 0
              puts "\e[32m✓ All #{checked} specs matched across #{adapters.size} adapters\e[0m"
            else
              puts "\e[32m#{matched} matched\e[0m, \e[31m#{diff_count} different\e[0m"
            end

            puts "  Checked: #{checked}/#{total} specs"
            puts "  Skipped: #{skipped} (no adapter supports)" if skipped > 0
            puts
          end
        end
      end
    end
  end
end
