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

          options = parse_options(args)

          if options[:adapters].empty? && !options[:all]
            $stderr.puts "Error: Specify --all or --adapters=LIST"
            $stderr.puts "Run 'liquid-spec matrix --help' for usage"
            exit(1)
          end

          run_matrix(options)
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
          # Load specs
          specs = load_specs(options)

          if specs.empty?
            puts "No specs to run"
            return
          end

          puts "Running #{specs.size} spec(s) across #{adapters.size} adapter(s)..."
          puts ""

          # Run ALL specs with ALL adapters in a single fork
          # This is much faster than forking per-spec or per-adapter
          print("  Running specs")
          $stdout.flush
          all_results = run_all_specs_all_adapters(specs, adapters)
          puts " done"
          puts ""

          # Find differences
          differences = []
          max_failures = options[:max_failures]
          stopped_early = false
          specs_checked = 0
          identical_count = 0

          specs.each do |spec|
            specs_checked += 1
            spec_results = {}
            adapters.each do |adapter|
              spec_results[adapter[:name]] = all_results[adapter[:name]][spec.name]
            end

            # Check for differences
            outputs = spec_results.values.map { |r| r[:output] || r[:error] }
            if outputs.uniq.size > 1
              differences << { spec: spec, results: spec_results }

              if max_failures && differences.size >= max_failures
                stopped_early = true
                break
              end
            else
              identical_count += 1
            end
          end

          # Summary header
          puts "=" * 70
          puts "MATRIX RESULTS"
          puts "=" * 70
          puts ""
          puts "Adapters: #{adapters.map { |a| a[:name] }.join(", ")}"
          puts ""

          if differences.empty?
            puts "\e[32m✓ All #{specs.size} specs produced identical output across all adapters\e[0m"
          else
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

              # Group adapters by output
              output_groups = {}
              diff[:results].each do |adapter_name, result|
                output = result[:error] ? "ERROR: #{result[:error]}" : result[:output]
                output_groups[output] ||= []
                output_groups[output] << adapter_name
              end

              output_groups.each do |output, adapter_names|
                puts "\e[2mAdapters:\e[0m #{adapter_names.join(", ")}"
                puts "\e[2mOutput:\e[0m"
                print_output(output)
                puts ""
              end
            end

            puts "=" * 70
            puts ""
            if stopped_early
              puts "\e[32m#{identical_count} identical\e[0m, \e[31m#{differences.size} different\e[0m (checked #{specs_checked}/#{specs.size}, stopped at max-failures)"
              puts "Run with --no-max-failures to see all differences"
            else
              puts "\e[32m#{identical_count} identical\e[0m, \e[31m#{differences.size} different\e[0m"
            end
            exit(1)
          end
        end

        def self.load_specs(options)
          # Load liquid first (required for yaml_initializer)
          require "liquid"

          # Load spec components - need deps/liquid_ruby for test drops
          require "liquid/spec"
          require "liquid/spec/suite"
          require "liquid/spec/deps/liquid_ruby"
          require "liquid/spec/yaml_initializer"

          specs = []

          # Load specs from suite
          case options[:suite]
          when :all
            Liquid::Spec::Suite.all.each do |suite|
              specs.concat(suite.specs)
            end
          else
            suite = Liquid::Spec::Suite.find(options[:suite])
            specs = suite ? suite.specs : []
          end

          # Add custom specs
          options[:add_specs].each do |glob|
            Dir[glob].each do |path|
              source = Liquid::Spec::Source.for(path)
              specs.concat(source.to_a)
            rescue => e
              $stderr.puts "Warning: Could not load #{path}: #{e.message}"
            end
          end

          # Filter by name
          if options[:filter]
            specs = specs.select { |s| s.name =~ options[:filter] }
          end

          specs
        end

        def self.run_all_specs_all_adapters(specs, adapters)
          # Fork once to run ALL specs with ALL adapters
          # This minimizes process overhead
          reader, writer = IO.pipe

          pid = fork do
            reader.close

            begin
              # Load all adapters
              loaded_adapters = {}
              adapters.each do |adapter_info|
                adapter = LiquidSpec::Adapter.load(adapter_info[:path])
                adapter.run_setup!
                loaded_adapters[adapter_info[:name]] = adapter
              end

              # Run all specs with all adapters
              results = {}
              adapters.each do |adapter_info|
                adapter = loaded_adapters[adapter_info[:name]]
                results[adapter_info[:name]] = {}

                specs.each do |spec|
                  results[adapter_info[:name]][spec.name] = adapter.run_spec(spec)
                end
              end

              Marshal.dump(results, writer)
            rescue SystemExit, Interrupt, SignalException
              raise
            rescue Exception => e
              Marshal.dump({ _error: { class: e.class.name, message: e.message } }, writer)
            ensure
              writer.close
            end
          end

          writer.close
          result = Marshal.load(reader)
          reader.close
          Process.wait(pid)

          if result[:_error]
            # Something failed - return error for all specs
            error_msg = "#{result[:_error][:class]}: #{result[:_error][:message]}"
            adapters.each_with_object({}) do |adapter_info, h|
              h[adapter_info[:name]] = specs.each_with_object({}) do |spec, s|
                s[spec.name] = { output: nil, error: error_msg }
              end
            end
          else
            result
          end
        rescue => e
          # Fork failed - return error for all specs
          adapters.each_with_object({}) do |adapter_info, h|
            h[adapter_info[:name]] = specs.each_with_object({}) do |spec, s|
              s[spec.name] = { output: nil, error: e.message }
            end
          end
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
          case adapter_name
          when /liquid_c/
            begin
              require "liquid"
              require "liquid/c"
              defined?(Liquid::C) && Liquid::C.enabled ? :available : "liquid-c not enabled"
            rescue LoadError
              "liquid-c gem not installed"
            end
          when /activesupport/
            begin
              require "active_support"
              require "liquid"
              :available
            rescue LoadError => e
              e.message.include?("active_support") ? "activesupport gem not installed" : "liquid gem not installed"
            end
          when /liquid_ruby/
            begin
              require "liquid"
              :available
            rescue LoadError
              "liquid gem not installed"
            end
          else
            # Unknown adapter - assume available
            :available
          end
        end
      end
    end
  end
end
