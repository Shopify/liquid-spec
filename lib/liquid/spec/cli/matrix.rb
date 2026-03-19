# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "bench"
require_relative "benchmark"
require_relative "config"
require_relative "runs"

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
            -o, --output=DIR      Reports directory (default: $LIQUID_SPEC_REPORTS or #{Config::DEFAULT_REPORTS_DIR})
            --all                 Run all available adapters from examples/
            --adapter=PATH        Add a local adapter (can be used multiple times)
            --adapters=LIST       Comma-separated list of adapters to run
            --reference=NAME      Reference adapter (default: liquid_ruby)
            -n, --name PATTERN    Filter specs by name pattern
            -s, --suite SUITE     Spec suite: all, basics, liquid_ruby, etc.
            -b, --bench           Run timing suites as benchmarks, compare across adapters
            --profile             Profile with StackProf (use with --bench), outputs to /tmp/
            --max-failures N      Stop after N differences (default: 10)
            --no-max-failures     Show all differences (not recommended)
            -v, --verbose         Show detailed output
            -h, --help            Show this help

          Examples:
            liquid-spec matrix --all
            liquid-spec matrix --all --adapter=./my_adapter.rb
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

            # Use Runs class for adapter resolution
            runs = Runs.new
            runs.parse_options!(args)
            options = parse_options(args)
            options[:runs] = runs

            run_matrix(options)
          end

          private

          def parse_options(args)
            options = {
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
              when "--profile"
                options[:profile] = true
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
            runs = options[:runs]

            if runs.empty?
              $stderr.puts "Error: No adapters specified"
              $stderr.puts ""
              $stderr.puts "Usage:"
              $stderr.puts "  liquid-spec matrix --all"
              $stderr.puts "  liquid-spec matrix --adapters=liquid_ruby,liquid_c"
              $stderr.puts "  liquid-spec matrix --adapter=./my_adapter.rb"
              exit(1)
            end

            # Print summary of what we're running
            runs.print_summary

            # Load liquid first, then spec infrastructure
            require "liquid"
            require "liquid/spec"
            require "liquid/spec/deps/liquid_ruby"

            # Load adapters (for non-benchmark mode, we need them in-process)
            unless options[:bench]
              puts "Loading adapters..."
              adapters = load_adapters_from_runs(runs)

              if adapters.empty?
                $stderr.puts "Error: No adapters loaded"
                exit(1)
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
            else
              # Benchmark mode - delegate to bench command
              bench_args = []
              bench_args += ["--all"] if runs.adapters.size > 2
              runs.adapters.each { |a| bench_args += ["--adapter=#{a.path}"] } unless bench_args.include?("--all")
              bench_args += ["-n", options[:filter]] if options[:filter]
              bench_args += ["-s", options[:suite].to_s] if options[:suite] != :all
              Bench.run(bench_args)
              return
            end
          end

          def load_adapters_from_runs(runs)
            adapters = {}

            runs.adapters.each do |adapter_info|
              begin
                # Reset LiquidSpec state before loading each adapter
                reset_liquid_spec!

                adapter = Liquid::Spec::AdapterRunner.new(name: adapter_info.name)
                adapter.load_dsl(adapter_info.path)
                adapter.ensure_setup!
                adapters[adapter_info.name] = adapter
              rescue LiquidSpec::SkipAdapter => e
                $stderr.puts "Skipping #{adapter_info.name}: #{e.message}"
              rescue => e
                $stderr.puts "Warning: Failed to load #{adapter_info.name}: #{e.message}"
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

              # Check if all outputs match each other AND match expected (if specified)
              unique_outputs = ran_outputs.values.map { |v| v[:output] }.uniq
              adapters_match = unique_outputs.size == 1

              # Check against spec.expected if it exists
              expected_match = true
              if spec.expected
                reference_output = ran_outputs.values.first[:output]
                expected_match = reference_output == spec.expected
              end

              if adapters_match && expected_match
                matched += 1
                print(".") if verbose
              else
                # Build diff info - group adapters by their output
                first_output = ran_outputs.values.first[:output]
                diff_info = {
                  spec: spec,
                  outputs: outputs,
                  first_output: first_output,
                }
                # Add expected mismatch info if relevant
                if spec.expected && !expected_match
                  diff_info[:expected_mismatch] = true
                  diff_info[:expected] = spec.expected
                end
                differences << diff_info
                print("F") if verbose
              end
            end

            puts " done" unless verbose
            puts

            # Print results (limited by max_failures for display only)
            print_results_v2(differences, adapters, options, max_failures)
            print_summary(matched, differences.size, skipped, checked, specs.size, adapters)

            exit(1) if differences.any?
          end








          def format_number(num)
            return "0" if num.nil? || num.zero?
            num.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
          end

          def prepare_matrix_spec(spec, adapter)
            return nil unless adapter.can_run?(spec)

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

            ctx = adapter.ctx
            compile_block = adapter.instance_variable_get(:@compile_block)
            render_block = adapter.instance_variable_get(:@render_block)

            # Verify it works
            compile_block.call(ctx, spec.template, compile_options)
            actual = render_block.call(ctx, deep_copy(environment), render_options)
            return nil if spec.expected && actual.to_s != spec.expected

            {
              ctx: ctx,
              template: spec.template,
              compile_options: compile_options,
              environment: environment,
              render_options: render_options,
              compile_block: compile_block,
              render_block: render_block,
            }
          rescue
            nil
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

          def jit_status
            if defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?
              "zjit"
            elsif defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
              "yjit"
            else
              "off"
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

          def print_results_v2(differences, adapters, options, max_failures = nil)
            return if differences.empty?

            puts "=" * 70
            puts "DIFFERENCES"
            puts "=" * 70
            puts

            # Determine how many to print
            print_count = max_failures ? [differences.size, max_failures].min : differences.size

            differences.first(print_count).each_with_index do |diff, idx|
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

              # Show expected if there's a mismatch
              if diff[:expected_mismatch]
                puts "\e[2mExpected:\e[0m"
                print_output(diff[:expected])
                puts
              end

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

            # Show message if we truncated output
            if max_failures && differences.size > max_failures
              puts "-" * 70
              puts "\e[2m(... #{differences.size - max_failures} more differences not shown due to --max-failures #{max_failures} ...)\e[0m"
              puts
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
