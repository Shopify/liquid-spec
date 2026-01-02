# frozen_string_literal: true

require_relative "adapter_dsl"
require "timecop"

module Liquid
  module Spec
    module CLI
      # Matrix command - run specs across multiple adapters and compare results
      module Matrix
        TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze
        TEST_TZ = "America/New_York"

        MAX_FAILURES_DEFAULT = 10

        HELP = <<~HELP
          Usage: liquid-spec matrix [ADAPTER] [options]

          Run specs across multiple adapters and compare results.
          Shows differences between implementations.

          Requires Ruby 4.0+ with Ruby::Box for proper isolation, or set RUBY_BOX=1.

          Arguments:
            ADAPTER               Local adapter file (optional)

          Options:
            --all                 Run all example adapters from liquid-spec
            --adapters=LIST       Comma-separated list of adapters to run
            --add-specs=GLOB      Add additional spec files (can be used multiple times)
            -n, --name PATTERN    Filter specs by name pattern
            -s, --suite SUITE     Spec suite: all, liquid_ruby, basics, etc.
            --max-failures N      Stop after N differences (default: #{MAX_FAILURES_DEFAULT})
            --no-max-failures     Show all differences
            -v, --verbose         Show detailed output
            -h, --help            Show this help

          Available adapters (in liquid-spec):
            liquid_ruby                   Pure Ruby Liquid (lax mode)
            liquid_ruby_strict            Pure Ruby Liquid (strict mode)
            liquid_ruby_activesupport     Pure Ruby Liquid with ActiveSupport
            liquid_ruby_strict_activesupport  Strict mode with ActiveSupport
            liquid_c                      Liquid with liquid-c extension

          Examples:
            # Run all bundled adapters
            liquid-spec matrix --all

            # Run specific adapters
            liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_strict

            # Compare your adapter against bundled ones
            liquid-spec matrix my_adapter.rb --all

            # Add custom specs
            liquid-spec matrix --all --add-specs="my_specs/*.yml"

            # Filter to specific tests
            liquid-spec matrix --all -n "truncate"

        HELP

        def self.run(args)
          if args.empty? || args.include?("-h") || args.include?("--help")
            puts HELP
            return
          end

          # Check for Ruby::Box support
          unless ruby_box_available?
            $stderr.puts "Error: Matrix command requires Ruby::Box for proper adapter isolation."
            $stderr.puts ""
            $stderr.puts "Options:"
            $stderr.puts "  1. Use Ruby 4.0+ (has Ruby::Box built-in)"
            $stderr.puts "  2. Set RUBY_BOX=1 environment variable (if Ruby::Box gem is installed)"
            $stderr.puts ""
            exit(1)
          end

          options = parse_options(args)

          if options[:adapters].empty? && !options[:all]
            $stderr.puts "Error: Specify --all or --adapters=LIST"
            $stderr.puts "Run 'liquid-spec matrix --help' for usage"
            exit(1)
          end

          run_matrix(options)
        end

        def self.ruby_box_available?
          # Ruby::Box requires RUBY_BOX=1 to be enabled, even on Ruby 4.0+
          # Try to actually create a box to verify it works

          Ruby::Box.new
          true
        rescue NameError
          # Ruby::Box not defined (Ruby < 4.0 without gem)
          false
        rescue RuntimeError
          # Ruby::Box disabled (RUBY_BOX=1 not set)
          false
        end

        def self.parse_options(args)
          options = {
            local_adapter: nil,
            adapters: [],
            all: false,
            add_specs: [],
            filter: nil,
            suite: :all,
            verbose: false,
            max_failures: MAX_FAILURES_DEFAULT,
            reference: "liquid_ruby",
          }

          while args.any?
            arg = args.shift
            case arg
            when "--all"
              options[:all] = true
            when "--adapters"
              options[:adapters] = args.shift.split(",").map(&:strip)
            when /\A--adapters=(.+)\z/
              options[:adapters] = ::Regexp.last_match(1).split(",").map(&:strip)
            when "--reference"
              options[:reference] = args.shift
            when /\A--reference=(.+)\z/
              options[:reference] = ::Regexp.last_match(1)
            when "--add-specs"
              options[:add_specs] << args.shift
            when /\A--add-specs=(.+)\z/
              options[:add_specs] << ::Regexp.last_match(1)
            when "-n", "--name"
              pattern = args.shift
              options[:filter] = Regexp.new(pattern, Regexp::IGNORECASE)
            when /\A--name=(.+)\z/, /\A-n(.+)\z/
              options[:filter] = Regexp.new(::Regexp.last_match(1), Regexp::IGNORECASE)
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
            when /\A-/
              # Unknown option, ignore
            else
              # Assume it's a local adapter file
              if File.exist?(arg) || arg.end_with?(".rb")
                options[:local_adapter] = arg
              end
            end
          end

          options
        end

        def self.run_matrix(options)
          gem_root = File.expand_path("../../../../..", __FILE__)
          adapters_dir = File.join(gem_root, "examples")

          # Build list of adapters to run
          adapters = []

          # Add local adapter first if specified
          if options[:local_adapter]
            if File.exist?(options[:local_adapter])
              adapters << { name: File.basename(options[:local_adapter], ".rb"), path: File.expand_path(options[:local_adapter]) }
            else
              $stderr.puts "Error: Local adapter not found: #{options[:local_adapter]}"
              exit(1)
            end
          end

          # Add bundled adapters
          if options[:all]
            Dir[File.join(adapters_dir, "*.rb")].each do |path|
              name = File.basename(path, ".rb")
              adapters << { name: name, path: path }
            end
          else
            options[:adapters].each do |name|
              path = File.join(adapters_dir, "#{name}.rb")
              if File.exist?(path)
                adapters << { name: name, path: path }
              else
                $stderr.puts "Warning: Adapter not found: #{name}"
              end
            end
          end

          if adapters.empty?
            $stderr.puts "Error: No adapters to run"
            exit(1)
          end

          # Check dependencies and filter available adapters
          available_adapters = []
          skipped_adapters = []

          adapters.each do |adapter|
            status = check_adapter_dependencies(adapter[:name])
            if status == :available
              available_adapters << adapter
            else
              skipped_adapters << { adapter: adapter, reason: status }
            end
          end

          if available_adapters.empty?
            $stderr.puts "Error: No adapters available (all skipped due to missing dependencies)"
            exit(1)
          end

          puts "Running matrix with #{available_adapters.size} adapter(s):"
          available_adapters.each { |a| puts "  - #{a[:name]}" }
          if skipped_adapters.any?
            puts ""
            puts "Skipped (missing dependencies):"
            skipped_adapters.each { |s| puts "  - #{s[:adapter][:name]}: #{s[:reason]}" }
          end
          puts ""

          # Set timezone and freeze time
          original_tz = ENV["TZ"]
          ENV["TZ"] = TEST_TZ

          begin
            Timecop.freeze(TEST_TIME) do
              run_matrix_comparison(available_adapters, options)
            end
          ensure
            ENV["TZ"] = original_tz
          end
        end

        def self.run_matrix_comparison(adapters, options)
          reference_name = options[:reference]

          # Ensure reference adapter is in the list
          unless adapters.any? { |a| a[:name] == reference_name }
            $stderr.puts "Error: Reference adapter '#{reference_name}' not found in adapter list"
            $stderr.puts "Available: #{adapters.map { |a| a[:name] }.join(", ")}"
            exit(1)
          end

          # Load specs by suite
          specs_by_suite = load_specs_by_suite(options)
          total_specs = specs_by_suite.values.map(&:size).sum

          if total_specs == 0
            puts "No specs to run"
            return
          end

          puts "Running #{total_specs} spec(s) across #{adapters.size} adapter(s)..."
          puts "Reference: #{reference_name}"
          puts ""

          # Create isolated boxes for each adapter
          print("  Loading adapters...")
          $stdout.flush
          boxes = create_adapter_boxes(adapters)
          puts " done"

          # Check that at least some adapters loaded successfully
          loaded_count = boxes.values.count { |b| !b.nil? }
          if loaded_count == 0
            $stderr.puts ""
            $stderr.puts "Error: All adapters failed to load."
            $stderr.puts "Make sure RUBY_BOX=1 is set in your environment."
            exit(1)
          elsif loaded_count < boxes.size
            failed_adapters = boxes.select { |_, b| b.nil? }.keys
            $stderr.puts ""
            $stderr.puts "Warning: #{failed_adapters.size} adapter(s) failed to load: #{failed_adapters.join(", ")}"
            $stderr.puts "Results will only include: #{boxes.select { |_, b| !b.nil? }.keys.join(", ")}"
            $stderr.puts ""
          end

          # Track results per suite per adapter
          # suite_results[suite_id][adapter_name] = {
          #   total: N,     # total specs in suite
          #   agreed: N,    # specs where all adapters agreed (success or error)
          #   checked: N,   # specs that were checked
          # }
          suite_results = {}
          specs_by_suite.each_key do |suite_id|
            suite_results[suite_id] = {}
            adapters.each do |adapter|
              suite_results[suite_id][adapter[:name]] = {
                total: specs_by_suite[suite_id].size,
                agreed: 0,
                checked: 0,
              }
            end
          end

          # Run each spec across all boxes
          differences = []
          max_failures = options[:max_failures]
          stopped_early = false
          specs_checked = 0
          identical_count = 0

          print("  Running specs...")
          $stdout.flush

          catch(:max_failures_reached) do
            specs_by_suite.each do |suite_id, specs|
              specs.each do |spec|
                specs_checked += 1

                # Run this spec in all boxes
                spec_results = {}
                boxes.each do |name, box|
                  spec_results[name] = if box.nil?
                    { output: nil, error: "Adapter failed to load" }
                  else
                    box.run_spec(spec)
                  end
                end

                # Normalize outputs to strings for comparison
                # NOTE: We must convert to native strings because Ruby::Box returns
                # objects that may not compare equal across box boundaries
                spec_results.each do |_name, result|
                  if result[:output] && !result[:error]
                    result[:original_class] = result[:output].class.name.dup
                    output_str = result[:output].to_s
                    result[:output] = String.new(output_str, encoding: output_str.encoding)
                  elsif result[:error]
                    error_str = result[:error].to_s
                    result[:error] = String.new(error_str, encoding: error_str.encoding)
                  end
                end

                # Get expected output (normalized)
                expected = spec.expected
                String.new(expected.to_s, encoding: expected.to_s.encoding) if expected

                # Compare each adapter against the reference
                # Normalize outputs to comparable values
                normalized_outputs = spec_results.transform_values do |r|
                  r[:error] ? "ERROR:#{r[:error]}" : r[:output]
                end

                reference_output = normalized_outputs[reference_name]
                reference_result = spec_results[reference_name]

                # Check for type mismatches among successful results
                successful_results = spec_results.select { |_, r| r[:output] && !r[:error] }
                if successful_results.size > 1
                  classes = successful_results.values.map { |r| r[:original_class] }.compact.uniq
                  if classes.size > 1
                    spec_results.each do |_name, result|
                      result[:type_mismatch] = true if result[:original_class]
                    end
                  end
                end

                # Update per-adapter stats (comparing against reference)
                all_match_reference = true
                adapters.each do |adapter|
                  stats = suite_results[suite_id][adapter[:name]]
                  stats[:checked] += 1

                  adapter_output = normalized_outputs[adapter[:name]]
                  matches_reference = adapter_output == reference_output

                  # Check type mismatch if both succeeded
                  if matches_reference && reference_result[:original_class]
                    adapter_result = spec_results[adapter[:name]]
                    if adapter_result[:original_class] && adapter_result[:original_class] != reference_result[:original_class]
                      matches_reference = false
                      adapter_result[:type_mismatch] = true
                    end
                  end

                  stats[:agreed] += 1 if matches_reference
                  all_match_reference = false unless matches_reference
                end

                # Track differences for detailed output
                if all_match_reference
                  identical_count += 1
                else
                  differences << { spec: spec, results: spec_results, suite: suite_id, reference: reference_name }

                  if max_failures && differences.size >= max_failures
                    stopped_early = true
                    throw(:max_failures_reached)
                  end
                end

                # Progress indicator
                print(".") if specs_checked % 100 == 0
                $stdout.flush
              end
            end
          end

          puts " done"
          puts ""

          # Summary header
          puts "=" * 70
          puts "MATRIX RESULTS"
          puts "=" * 70
          puts ""
          puts "Adapters: #{adapters.map { |a| a[:name] }.join(", ")}"
          puts ""

          if differences.any?
            differences.each_with_index do |diff, idx|
              puts "-" * 70
              puts "\e[1m#{idx + 1}. #{diff[:spec].name}\e[0m"
              puts ""
              puts "\e[2mTemplate:\e[0m"
              if diff[:spec].template.include?("\n")
                diff[:spec].template.each_line { |l| puts "  #{l}" }
              else
                puts "  #{diff[:spec].template}"
              end
              puts ""

              # Check if this is a type-only mismatch
              type_mismatch = diff[:results].values.any? { |r| r[:type_mismatch] }

              # Group adapters by output (and type if type mismatch)
              output_groups = {}
              diff[:results].each do |adapter_name, result|
                output = result[:error] ? "ERROR: #{result[:error]}" : result[:output]
                key = type_mismatch ? [output, result[:original_class]] : [output, nil]
                output_groups[key] ||= []
                output_groups[key] << adapter_name
              end

              if type_mismatch
                puts "\e[33m⚠ Type mismatch (same string output, different types)\e[0m"
                puts ""
              end

              output_groups.each do |(output, type), adapter_names|
                puts "\e[2mAdapters:\e[0m #{adapter_names.join(", ")}"
                puts "\e[2mOutput:\e[0m"
                print_output(output)
                puts "\e[2mType:\e[0m #{type}" if type
                puts ""
              end
            end

            puts "=" * 70
            puts ""
            if stopped_early
              puts "\e[32m#{identical_count} matched reference\e[0m, \e[31m#{differences.size} different\e[0m (checked #{specs_checked}/#{total_specs}, stopped at max-failures)"
              puts "Run with --no-max-failures to see all differences"
            else
              puts "\e[32m#{identical_count} matched reference\e[0m, \e[31m#{differences.size} different\e[0m"
            end
          else
            puts "\e[32m✓ All #{total_specs} specs matched reference (#{reference_name})\e[0m"
          end

          # Print summary table
          puts ""
          print_summary_table(suite_results, adapters, specs_by_suite, options[:reference])

          exit(1) if differences.any?
        end

        def self.print_summary_table(suite_results, adapters, specs_by_suite, reference_name)
          puts "=" * 70
          puts "SUMMARY"
          puts "=" * 70
          puts ""

          suite_ids = suite_results.keys
          adapter_names = adapters.map { |a| a[:name] }

          # Group suites into: basics, others, custom
          basics_suites = suite_ids.select { |s| s == :basics }
          custom_suites = suite_ids.select { |s| s == :custom }
          other_suites = suite_ids - basics_suites - custom_suites

          # Build column groups: basics, others, and custom (if present)
          columns = []

          if basics_suites.any?
            basics_total = basics_suites.sum { |s| specs_by_suite[s].size }
            columns << { name: "basics (#{basics_total})", suites: basics_suites, total: basics_total }
          end

          if other_suites.any?
            others_total = other_suites.sum { |s| specs_by_suite[s].size }
            columns << { name: "others (#{others_total})", suites: other_suites, total: others_total }
          end

          if custom_suites.any?
            custom_total = custom_suites.sum { |s| specs_by_suite[s].size }
            columns << { name: "custom (#{custom_total})", suites: custom_suites, total: custom_total }
          end

          # Calculate column widths
          adapter_col_width = adapter_names.map(&:length).max
          adapter_col_width = [adapter_col_width, 10].max

          col_width = columns.map { |c| c[:name].length }.max
          col_width = [col_width, 14].max

          # Header row
          header = "Adapter".ljust(adapter_col_width)
          columns.each do |col|
            header += " | " + col[:name].center(col_width)
          end
          puts header
          puts "-" * header.length

          # Data rows (one per adapter, reference shown in bold)
          adapter_names.each do |adapter_name|
            is_reference = adapter_name == reference_name
            name_display = adapter_name.ljust(adapter_col_width)
            name_display = "\e[1m#{name_display}\e[0m" if is_reference

            row = name_display

            columns.each do |col|
              # Aggregate stats across all suites in this column
              total = col[:total]
              checked = col[:suites].sum { |s| suite_results[s][adapter_name][:checked] }
              agreed = col[:suites].sum { |s| suite_results[s][adapter_name][:agreed] }

              stats = { checked: checked, agreed: agreed }
              cell_text, cell_color = format_cell(stats, total)
              padded = cell_text.center(col_width)
              row += " | #{cell_color}#{padded}\e[0m"
            end

            puts row
          end

          puts ""
        end

        def self.format_cell(stats, total)
          checked = stats[:checked]
          agreed = stats[:agreed]

          if agreed == total
            # Green checkmark - all specs agreed across adapters
            ["✓", "\e[32m"]
          elsif checked < total
            # Yellow warning - didn't check all specs (stopped early)
            ["⚠ #{agreed}/#{checked}", "\e[33m"]
          else
            # Red X - some specs disagreed between adapters
            ["✗ #{agreed}/#{total}", "\e[31m"]
          end
        end

        def self.load_specs(options)
          load_specs_by_suite(options).values.flatten
        end

        def self.load_specs_by_suite(options)
          # Load liquid first (required for yaml_initializer)
          # IMPORTANT: Prevent liquid-c from loading in the main process
          # because native extensions pollute Ruby::Box instances
          ENV["LIQUID_C_DISABLE"] = "1"
          require "liquid"

          # Load spec components - need deps/liquid_ruby for test drops
          require "liquid/spec"
          require "liquid/spec/suite"
          require "liquid/spec/deps/liquid_ruby"
          require "liquid/spec/yaml_initializer"

          specs_by_suite = {}

          # Load specs from suite
          case options[:suite]
          when :all
            Liquid::Spec::Suite.all.each do |suite|
              specs_by_suite[suite.id] = suite.specs
            end
          else
            suite = Liquid::Spec::Suite.find(options[:suite])
            if suite
              specs_by_suite[suite.id] = suite.specs
            end
          end

          # Add custom specs under a special "custom" suite
          custom_specs = []
          options[:add_specs].each do |glob|
            Dir[glob].each do |path|
              source = Liquid::Spec::Source.for(path)
              custom_specs.concat(source.to_a)
            rescue => e
              $stderr.puts "Warning: Could not load #{path}: #{e.message}"
            end
          end
          specs_by_suite[:custom] = custom_specs if custom_specs.any?

          # Filter by name
          if options[:filter]
            specs_by_suite.transform_values! do |specs|
              specs.select { |s| s.name =~ options[:filter] }
            end
            # Remove empty suites
            specs_by_suite.delete_if { |_, specs| specs.empty? }
          end

          specs_by_suite
        end

        # Wrapper around Ruby::Box that provides a simple interface for running specs
        class AdapterBox
          attr_reader :name, :path, :box

          def initialize(name:, path:)
            @name = name
            @path = path
            @box = Ruby::Box.new

            # Add load paths so box can find gems
            $LOAD_PATH.each { |p| @box.load_path << p }

            # Load the adapter DSL in the box
            @box.require(File.expand_path("adapter_dsl.rb", __dir__))

            # Load the adapter file in the box
            @box.load(path)

            # Run setup and cache the LiquidSpec module reference
            @liquid_spec = @box.const_get(:LiquidSpec)
            @liquid_spec.run_setup!

            # Load spec support classes inside the box
            @box.require("liquid/spec/deps/liquid_ruby")

            # Get box-native Hash and Array classes for deep_copy
            @box_hash = @box.const_get(:Hash)
            @box_array = @box.const_get(:Array)
          end

          def run_spec(spec)
            # Reset global state before each spec run to ensure drop isolation
            @box.eval("LiquidSpec::Globals.reset!")

            compile_options = { line_numbers: true }
            compile_options[:error_mode] = spec.error_mode.to_sym if spec.error_mode

            template = @liquid_spec.do_compile(spec.template, compile_options)

            render_options = {
              registers: {},
              strict_errors: false,
            }
            render_options[:error_mode] = spec.error_mode.to_sym if spec.error_mode

            # Deep copy environment into box-native objects
            env = deep_copy_to_box(spec.environment || {})
            output = @liquid_spec.do_render(template, env, render_options)
            { output: output, error: nil }
          rescue Exception => e
            { output: nil, error: "#{e.class}: #{e.message}" }
          end

          private

          # Recursively copy a value into box-native objects
          def deep_copy_to_box(val)
            case val
            when Hash
              result = @box_hash.new
              val.each { |k, v| result[deep_copy_to_box(k)] = deep_copy_to_box(v) }
              result
            when Array
              result = @box_array.new
              val.each { |v| result << deep_copy_to_box(v) }
              result
            else
              # Primitives and drop objects pass through
              # Drops now use LiquidSpec::Globals for state, which is reset per-spec
              val
            end
          end
        end

        def self.create_adapter_boxes(adapters)
          boxes = {}
          adapters.each do |adapter_info|
            boxes[adapter_info[:name]] = AdapterBox.new(
              name: adapter_info[:name],
              path: adapter_info[:path],
            )
          rescue Exception => e
            $stderr.puts "Warning: Failed to load adapter #{adapter_info[:name]}: #{e.message}"
            boxes[adapter_info[:name]] = nil
          end
          boxes
        end

        def self.print_output(output)
          if output.nil?
            puts "  \e[2m(nil)\e[0m"
          elsif output.to_s.empty?
            puts "  \e[2m(empty string)\e[0m"
          elsif output.to_s.include?("\n")
            output.to_s.each_line.with_index do |line, i|
              puts "  #{i + 1}: #{line.chomp.inspect}"
            end
          else
            puts "  #{output.inspect}"
          end
        end

        def self.check_adapter_dependencies(adapter_name)
          # Check if gems are available without loading them
          # (loading liquid-c would pollute the main process and break Ruby::Box isolation)
          case adapter_name
          when /liquid_c/
            gem_available?("liquid-c") ? :available : "liquid-c gem not installed"
          when /activesupport/
            gem_available?("activesupport") ? :available : "activesupport gem not installed"
          when /liquid_ruby/
            gem_available?("liquid") ? :available : "liquid gem not installed"
          else
            # Unknown adapter - assume available
            :available
          end
        end

        def self.gem_available?(name)
          Gem::Specification.find_by_name(name)
          true
        rescue Gem::MissingSpecError
          false
        end
      end
    end
  end
end
