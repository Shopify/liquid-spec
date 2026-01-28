# frozen_string_literal: true

require_relative "config"

module Liquid
  module Spec
    module CLI
      # Manages adapter resolution and run configuration.
      # Handles --adapter, --adapters params, resolves paths, and tracks
      # whether adapters are builtin (from examples/) or local.
      class Runs
        Adapter = Struct.new(:name, :path, :builtin, keyword_init: true)

        attr_reader :adapters, :output_dir, :extra_specs

        def initialize
          @adapters = []
          @extra_specs = []
          @output_dir = nil
        end

        # Parse adapter-related options from args.
        # Mutates args to remove consumed options.
        # Returns remaining args.
        def parse_options!(args)
          remaining = []

          while args.any?
            arg = args.shift
            case arg
            when /\A-o=(.+)\z/, /\A--output=(.+)\z/
              @output_dir = ::Regexp.last_match(1)
            when "-o", "--output"
              @output_dir = args.shift
            when /\A--adapter=(.+)\z/
              add_adapter(::Regexp.last_match(1))
            when "--adapter"
              add_adapter(args.shift)
            when /\A--adapters=(.+)\z/
              ::Regexp.last_match(1).split(",").map(&:strip).each { |a| add_adapter(a) }
            when "--adapters"
              args.shift.split(",").map(&:strip).each { |a| add_adapter(a) }
            when /\A--add-specs=(.+)\z/
              @extra_specs << ::Regexp.last_match(1)
            when "--add-specs"
              @extra_specs << args.shift
            when "--all"
              add_all_builtin_adapters
            else
              remaining << arg
            end
          end

          # Replace args contents with remaining
          args.replace(remaining)
          args
        end

        # Add an adapter by name or path
        def add_adapter(name_or_path)
          resolved = resolve_adapter(name_or_path)
          unless resolved
            $stderr.puts "\e[31mError: Adapter not found: #{name_or_path}\e[0m"
            $stderr.puts ""
            $stderr.puts "Searched in:"
            $stderr.puts "  - Current directory: #{Dir.pwd}"
            $stderr.puts "  - Examples directory: #{examples_dir}"
            $stderr.puts ""
            $stderr.puts "Tried:"
            $stderr.puts "  - #{name_or_path}"
            $stderr.puts "  - #{name_or_path}.rb" unless name_or_path.end_with?(".rb")
            exit(1)
          end
          @adapters << resolved unless @adapters.any? { |a| a.path == resolved.path }
        end

        # Add all builtin adapters from examples/
        def add_all_builtin_adapters
          Dir[File.join(examples_dir, "*.rb")].sort.each do |path|
            name = File.basename(path, ".rb")
            @adapters << Adapter.new(name: name, path: path, builtin: true)
          end

          # Ensure liquid_ruby is first (reference)
          if (idx = @adapters.index { |a| a.name == "liquid_ruby" })
            liquid_ruby = @adapters.delete_at(idx)
            @adapters.unshift(liquid_ruby)
          end
        end

        # Get the resolved output directory
        def reports_dir
          Config.reports_dir(@output_dir)
        end

        # Print summary of what will be run
        def print_summary
          puts ""
          puts "\e[1mAdapters:\e[0m"
          @adapters.each do |adapter|
            label = adapter.builtin ? "\e[2m(builtin)\e[0m" : "\e[33m(local)\e[0m"
            puts "  #{adapter.name.ljust(40)} #{label}"
            puts "    \e[2m#{adapter.path}\e[0m" unless adapter.builtin
          end

          if @extra_specs.any?
            puts ""
            puts "\e[1mExtra specs:\e[0m"
            @extra_specs.each do |spec_glob|
              matching = Dir.glob(spec_glob)
              puts "  #{spec_glob} \e[2m(#{matching.size} files)\e[0m"
            end
          end

          puts ""
        end

        # Get adapter names
        def adapter_names
          @adapters.map(&:name)
        end

        # Get adapter paths (for subprocess invocation)
        def adapter_paths
          @adapters.map(&:path)
        end

        # Find adapter by name
        def find_adapter(name)
          @adapters.find { |a| a.name == name }
        end

        # Check if we have any adapters
        def empty?
          @adapters.empty?
        end

        private

        def resolve_adapter(name_or_path)
          # Try as-is first (could be full path or relative path)
          if File.exist?(name_or_path)
            return make_adapter(name_or_path, local: true)
          end

          # Try with .rb extension
          if !name_or_path.end_with?(".rb") && File.exist?("#{name_or_path}.rb")
            return make_adapter("#{name_or_path}.rb", local: true)
          end

          # Try in examples directory (builtin)
          examples_path = File.join(examples_dir, "#{name_or_path}.rb")
          if File.exist?(examples_path)
            return make_adapter(examples_path, local: false)
          end

          # Try in examples directory without .rb (in case they passed with extension)
          if name_or_path.end_with?(".rb")
            base_name = name_or_path.chomp(".rb")
            examples_path = File.join(examples_dir, "#{base_name}.rb")
            if File.exist?(examples_path)
              return make_adapter(examples_path, local: false)
            end
          end

          nil
        end

        def make_adapter(path, local:)
          full_path = File.realpath(path)
          name = File.basename(full_path, ".rb")
          Adapter.new(name: name, path: full_path, builtin: !local)
        end

        def examples_dir
          @examples_dir ||= File.expand_path("../../../../examples", __dir__)
        end
      end
    end
  end
end
