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
            --adapters=LIST       Comma-separated list of adapters to run
            --reference=NAME      Reference adapter (default: liquid_ruby)
            -n, --name PATTERN    Filter specs by name pattern
            -s, --suite SUITE     Spec suite: all, basics, liquid_ruby, etc.
            --max-failures N      Stop after N differences (default: 10)
            --no-max-failures     Show all differences
            -v, --verbose         Show detailed output
            -h, --help            Show this help

          Examples:
            liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax
            liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax -n truncate
            liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax -s basics

        HELP

        class << self
          def run(args)
            if args.empty? || args.include?("-h") || args.include?("--help")
              puts HELP
              return
            end

            options = parse_options(args)
            run_matrix(options)
          end

          private

          def parse_options(args)
            options = {
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
            if options[:adapters].empty?
              $stderr.puts "Error: Specify --adapters=LIST"
              $stderr.puts "Example: --adapters=liquid_ruby,liquid_ruby_lax"
              exit(1)
            end

            # Load spec infrastructure
            require "liquid/spec"

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
            reference = adapters[reference_name]
            other_adapters = adapters.reject { |name, _| name == reference_name }

            differences = []
            matched = 0
            skipped = 0
            checked = 0

            max_failures = options[:max_failures]
            verbose = options[:verbose]

            print("Running #{specs.size} specs: ")
            $stdout.flush

            specs.each do |spec|
              # Run on reference
              ref_result = reference.run_single(spec)

              if ref_result.skipped?
                skipped += 1
                print("s") if verbose
                next
              end

              checked += 1
              ref_output = normalize_output(ref_result)

              # Compare with other adapters
              spec_diffs = {}
              other_adapters.each do |name, adapter|
                result = adapter.run_single(spec)

                if result.skipped?
                  spec_diffs[name] = { skipped: true }
                  next
                end

                output = normalize_output(result)
                unless outputs_match?(ref_output, output)
                  spec_diffs[name] = { output: output, ref_output: ref_output }
                end
              end

              if spec_diffs.empty? || spec_diffs.values.all? { |d| d[:skipped] }
                matched += 1
                print(".") if verbose
              else
                differences << { spec: spec, ref_output: ref_output, diffs: spec_diffs }
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
            print_results(differences, reference_name, adapters, options)
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

          def print_results(differences, reference_name, adapters, options)
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

              # Group outputs
              outputs = { reference_name => diff[:ref_output] }
              diff[:diffs].each do |name, d|
                outputs[name] = d[:skipped] ? "(skipped)" : d[:output]
              end

              # Find adapters not in diffs (they matched reference)
              adapters.keys.each do |name|
                next if name == reference_name
                next if diff[:diffs].key?(name)

                outputs[name] = diff[:ref_output] # matched
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
            puts "  Skipped: #{skipped} (reference doesn't support)" if skipped > 0
            puts
          end
        end
      end
    end
  end
end
