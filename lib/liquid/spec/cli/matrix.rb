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
            --max-failures N      Stop after N differences (default: 10)
            --no-max-failures     Show all differences
            -v, --verbose         Show detailed output
            -h, --help            Show this help

          Examples:
            liquid-spec matrix --all
            liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax
            liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax -n truncate

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

            # Load specs
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

            # Load adapters
            puts "Loading adapters..."
            adapters = load_adapters(options[:adapters])

            if adapters.empty?
              $stderr.puts "Error: No adapters loaded"
              exit(1)
            end

            # Verify reference adapter exists
            reference_name = options[:reference]
            unless adapters.key?(reference_name)
              $stderr.puts "Error: Reference adapter '#{reference_name}' not found"
              $stderr.puts "Available: #{adapters.keys.join(", ")}"
              exit(1)
            end

            puts "Loaded #{adapters.size} adapter(s): #{adapters.keys.join(", ")}"
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
              path = File.join(examples_dir, "#{name}.rb")
              unless File.exist?(path)
                $stderr.puts "Warning: Adapter not found: #{name}"
                next
              end

              begin
                # Reset LiquidSpec state before loading each adapter
                reset_liquid_spec!

                adapter = Liquid::Spec::AdapterRunner.new(name: name)
                adapter.load_dsl(path)
                adapter.ensure_setup!
                adapters[name] = adapter
              rescue => e
                $stderr.puts "Warning: Failed to load #{name}: #{e.message}"
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

                if result.skipped?
                  outputs[name] = { skipped: true }
                else
                  outputs[name] = { output: normalize_output(result) }
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
