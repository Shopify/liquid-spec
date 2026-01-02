# frozen_string_literal: true

require "yaml"
require_relative "lazy_spec"

module Liquid
  module Spec
    # Loads specs from YAML files without instantiating drop objects
    module SpecLoader
      class << self
        # Ensure test infrastructure is loaded before parsing YAML
        def ensure_test_infrastructure!
          return if @infrastructure_loaded

          # Load test drops and yaml initializer for custom YAML tags
          # These must be loaded AFTER liquid gem is loaded
          if defined?(Liquid::Template)
            require_relative "deps/liquid_ruby"
            require_relative "yaml_initializer"
          end

          @infrastructure_loaded = true
        end

        # Load all specs from the default suites
        def load_all(suite: :all, filter: nil)
          require_relative "suite"
          ensure_test_infrastructure!

          specs = []

          case suite
          when :all
            Suite.defaults.each do |s|
              specs.concat(load_suite(s))
            end
          else
            s = Suite.find(suite)
            specs.concat(load_suite(s)) if s
          end

          # Apply filter if provided
          if filter
            regex = filter.is_a?(Regexp) ? filter : Regexp.new(filter.to_s, Regexp::IGNORECASE)
            specs = specs.select { |s| s.name =~ regex }
          end

          specs
        end

        # Load specs from a suite
        def load_suite(suite)
          specs = []
          suite_path = suite.path

          # Load YAML spec files
          Dir[File.join(suite_path, "*.yml")].each do |file|
            next if File.basename(file) == "suite.yml"

            begin
              file_specs = load_yaml_file(file, suite: suite)
              specs.concat(file_specs)
            rescue ArgumentError, NameError => e
              if e.message.include?("undefined class/module") || e.message.include?("uninitialized constant")
                warn("Skipping #{file}: missing class/module")
              else
                raise
              end
            end
          end

          # Load directory-based specs (template.liquid + environment.yml + expected.html)
          Dir[File.join(suite_path, "*")].each do |dir|
            next unless File.directory?(dir)
            next unless File.exist?(File.join(dir, "template.liquid"))

            spec = load_directory_spec(dir, suite: suite)
            specs << spec if spec
          end

          specs
        end

        # Load specs from a single YAML file
        # Returns array of LazySpec objects
        def load_yaml_file(path, suite: nil)
          ensure_test_infrastructure!
          content = File.read(path)
          specs = []

          # Use unsafe_load since spec files may contain custom classes
          data = YAML.unsafe_load(content)
          return specs unless data

          # Extract metadata if present
          metadata = {}
          spec_list = []

          if data.is_a?(Hash) && data.key?("_metadata")
            metadata = data["_metadata"] || {}
            spec_list = data["specs"] || []
          elsif data.is_a?(Array)
            spec_list = data
          elsif data.is_a?(Hash) && data.key?("specs")
            spec_list = data["specs"] || []
          end

          # Build source-level defaults
          source_hint = metadata["hint"]
          source_doc = metadata["doc"]
          source_required_options = (metadata["required_options"] || {}).transform_keys(&:to_sym)
          minimum_complexity = suite&.minimum_complexity || metadata["minimum_complexity"] || 1000

          # Suite defaults
          suite_defaults = suite&.defaults || {}
          default_render_errors = suite_defaults[:render_errors]

          # Convert each spec hash to LazySpec
          spec_list.each do |spec_data|
            next unless spec_data.is_a?(Hash)

            # Determine render_errors: spec > metadata > suite default
            spec_render_errors = if spec_data.key?("render_errors")
              spec_data["render_errors"]
            elsif metadata.key?("render_errors")
              metadata["render_errors"]
            else
              default_render_errors
            end

            spec = LazySpec.new(
              name: spec_data["name"],
              template: spec_data["template"],
              expected: spec_data["expected"],
              errors: spec_data["errors"] || {},
              hint: spec_data["hint"],
              doc: spec_data["doc"] || source_doc,
              complexity: spec_data["complexity"] || minimum_complexity,
              error_mode: spec_data["error_mode"]&.to_sym,
              render_errors: spec_render_errors || false,
              required_features: spec_data["required_features"] || [],
              source_file: path,
              line_number: nil,
              raw_environment: spec_data["environment"] || {},
              raw_filesystem: spec_data["filesystem"] || {},
              source_hint: source_hint,
              source_required_options: source_required_options,
            )

            specs << spec
          end

          specs
        rescue Psych::SyntaxError => e
          warn("YAML syntax error in #{path}: #{e.message}")
          []
        rescue ArgumentError, NameError => e
          # Handle undefined classes in YAML
          if e.message.include?("undefined class/module") || e.message.include?("uninitialized constant")
            warn("Skipping #{path}: #{e.message.split("\n").first}")
          else
            warn("Error loading #{path}: #{e.message}")
          end
          []
        rescue StandardError => e
          warn("Error loading #{path}: #{e.class}: #{e.message.split("\n").first}")
          []
        end

        # Load a spec from a directory structure
        # (template.liquid, environment.yml, expected.html)
        def load_directory_spec(dir, suite: nil)
          template_file = File.join(dir, "template.liquid")
          return unless File.exist?(template_file)

          template = File.read(template_file)
          name = File.basename(dir)

          # Load environment
          env_file = File.join(dir, "environment.yml")
          raw_environment = if File.exist?(env_file)
            YAML.unsafe_load(File.read(env_file)) || {}
          else
            {}
          end

          # Load expected output
          expected_file = File.join(dir, "expected.html")
          expected = File.exist?(expected_file) ? File.read(expected_file) : nil

          minimum_complexity = suite&.minimum_complexity || 1000

          LazySpec.new(
            name: name,
            template: template,
            expected: expected,
            errors: {},
            hint: nil,
            complexity: minimum_complexity,
            error_mode: nil,
            render_errors: false,
            required_features: suite&.required_features || [],
            source_file: template_file,
            line_number: nil,
            raw_environment: raw_environment,
            raw_filesystem: {},
            source_hint: suite&.hint,
            source_required_options: {},
          )
        end

        # Load specs from a single file (YAML or directory)
        def load_file(path, suite: nil)
          if File.directory?(path)
            spec = load_directory_spec(path, suite: suite)
            spec ? [spec] : []
          elsif path.end_with?(".yml")
            load_yaml_file(path, suite: suite)
          else
            []
          end
        end
      end
    end
  end
end
