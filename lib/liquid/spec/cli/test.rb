# frozen_string_literal: true

module Liquid
  module Spec
    module CLI
      # Test command - run specs against all available example adapters
      module Test
        HELP = <<~HELP
          Usage: liquid-spec test [options]

          Run specs against all available example adapters in the gem.
          Automatically skips adapters whose dependencies are not installed.

          Options:
            -c, --compare         Compare adapter output against reference liquid-ruby
            -v, --verbose         Show verbose output
            -h, --help            Show this help

          Examples:
            liquid-spec test                    # Run all available adapters
            liquid-spec test --compare          # Compare mode
            liquid-spec test -v                 # Verbose output

        HELP

        def self.run(args)
          if args.include?("-h") || args.include?("--help")
            puts HELP
            return
          end

          options = parse_options(args)
          run_all_adapters(options)
        end

        def self.parse_options(args)
          options = {}

          while args.any?
            arg = args.shift
            case arg
            when "-c", "--compare"
              options[:compare] = true
            when "-v", "--verbose"
              options[:verbose] = true
            end
          end

          options
        end

        def self.run_all_adapters(options)
          # Find example adapters in the gem
          gem_root = File.expand_path("../../../../..", __FILE__)
          adapters_dir = File.join(gem_root, "examples")

          unless File.directory?(adapters_dir)
            $stderr.puts "Error: Examples directory not found: #{adapters_dir}"
            exit(1)
          end

          adapters = Dir[File.join(adapters_dir, "*.rb")]

          if adapters.empty?
            $stderr.puts "No example adapters found in #{adapters_dir}"
            exit(1)
          end

          available = []
          skipped = []

          adapters.each do |adapter|
            adapter_name = File.basename(adapter, ".rb")
            status = check_adapter_dependencies(adapter_name)

            if status == :available
              available << adapter
            else
              skipped << [adapter, status]
            end
          end

          puts "Testing #{available.size} adapter(s)..."
          puts ""

          skipped.each do |adapter, reason|
            puts "SKIP: #{File.basename(adapter)} (#{reason})"
          end
          puts "" if skipped.any?

          failed = []
          available.each do |adapter|
            puts "=" * 60
            puts "Testing: #{File.basename(adapter)}"
            puts "=" * 60
            puts ""

            cmd = [RbConfig.ruby, File.join(gem_root, "bin", "liquid-spec"), "run", adapter]
            cmd << "--compare" if options[:compare]
            cmd << "-v" if options[:verbose]

            success = system(*cmd)
            failed << adapter unless success

            puts ""
          end

          puts "=" * 60
          puts "Summary"
          puts "=" * 60
          puts "Passed: #{available.size - failed.size}/#{available.size}"
          puts "Skipped: #{skipped.size}" if skipped.any?

          if failed.any?
            puts ""
            puts "Failed adapters:"
            failed.each { |a| puts "  - #{File.basename(a)}" }
            exit(1)
          end
        end

        def self.check_adapter_dependencies(adapter_name)
          case adapter_name
          when "liquid_c"
            begin
              require "liquid"
              require "liquid/c"
              defined?(Liquid::C) && Liquid::C.enabled ? :available : "liquid-c not enabled"
            rescue LoadError
              "liquid-c gem not installed"
            end
          when "liquid_ruby", "liquid_ruby_strict"
            begin
              require "liquid"
              :available
            rescue LoadError
              "liquid gem not installed"
            end
          else
            # Unknown adapter - assume available and let it fail if deps missing
            :available
          end
        end
      end
    end
  end
end
