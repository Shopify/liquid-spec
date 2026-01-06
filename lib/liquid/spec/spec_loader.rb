# frozen_string_literal: true

require "yaml"
require_relative "lazy_spec"

module Liquid
  module Spec
    # Registry for instantiating custom objects used in specs
    # Maps "instantiate:ClassName" strings to lambdas that create instances
    module ClassRegistry
      @factories = {}

      class << self
        # Register a factory lambda for a class name
        # The lambda receives params hash and returns an instance
        def register(name, klass = nil, &block)
          if block_given?
            @factories[name] = block
          elsif klass
            # Default factory: call klass.new(params)
            @factories[name] = ->(params) { klass.new(params) }
          end
        end

        # Instantiate an object by name with given params
        def instantiate(name, params)
          factory = @factories[name]
          return unless factory

          factory.call(params)
        end

        def registered?(name)
          @factories.key?(name)
        end

        def all
          @factories.dup
        end

        def clear!
          @factories.clear
        end
      end
    end

    # Loads specs from YAML files without instantiating drop objects
    module SpecLoader
      class << self
        # Load all specs from the default suites
        def load_all(suite: :all, filter: nil)
          require_relative "suite"

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
          content = File.read(path)
          specs = []

          # Fail fast if file contains !ruby/ tags - these must be converted to instantiate format
          if content.include?("!ruby/")
            # Find the line numbers with !ruby/ tags
            bad_lines = []
            content.each_line.with_index do |line, idx|
              bad_lines << (idx + 1) if line.include?("!ruby/")
            end
            raise "YAML file contains !ruby/ tags which are not allowed. " \
              "Convert to instantiate format.\n" \
              "File: #{path}\n" \
              "Lines: #{bad_lines.first(10).join(", ")}#{bad_lines.size > 10 ? "..." : ""}"
          end

          # Parse YAML AST to extract line numbers
          doc = Psych.parse(content)
          line_numbers = extract_line_numbers_from_ast(doc) if doc

          # Safe to load - no custom objects
          data = safe_load_with_permitted_classes(content)
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
          default_error_mode = suite_defaults[:error_mode]&.to_sym
          default_expected = suite_defaults[:expected]
          skip_validation = suite&.timings?

          # Convert each spec hash to LazySpec
          spec_list.each_with_index do |spec_data, idx|
            next unless spec_data.is_a?(Hash)

            # Determine render_errors: spec > metadata > suite default
            spec_render_errors = if spec_data.key?("render_errors")
              spec_data["render_errors"]
            elsif metadata.key?("render_errors")
              metadata["render_errors"]
            else
              default_render_errors
            end

            # Determine error_mode: spec > metadata > suite default
            spec_error_mode = if spec_data.key?("error_mode")
              spec_data["error_mode"]&.to_sym
            elsif source_required_options.key?(:error_mode)
              source_required_options[:error_mode]
            else
              default_error_mode
            end

            # Keep environment as-is (may contain tagged objects or plain data)
            raw_env = spec_data["environment"] || {}

            # Process instantiate strings in environment
            raw_env = process_instantiate_strings(raw_env)

            # Get line number for this spec from AST
            spec_line_number = line_numbers ? line_numbers[idx] : nil

            # Determine expected: spec > suite default
            spec_expected = spec_data.key?("expected") ? spec_data["expected"] : default_expected

            spec = LazySpec.new(
              name: spec_data["name"],
              template: spec_data["template"],
              expected: spec_expected,
              errors: spec_data["errors"] || {},
              hint: spec_data["hint"],
              doc: spec_data["doc"] || source_doc,
              complexity: spec_data["complexity"] || minimum_complexity,
              error_mode: spec_error_mode,
              render_errors: spec_render_errors || false,
              required_features: spec_data["required_features"] || [],
              source_file: path,
              line_number: spec_line_number,
              raw_environment: raw_env,
              raw_filesystem: spec_data["filesystem"] || {},
              raw_template_factory: spec_data["template_factory"],
              source_hint: source_hint,
              source_required_options: source_required_options,
            )

            # Validate spec - raises SpecValidationError if invalid
            # Skip validation for timing/benchmark suites
            spec.validate! unless skip_validation

            specs << spec
          end

          specs
        rescue SpecValidationError
          # Re-raise validation errors - these are fatal
          raise
        rescue Psych::SyntaxError => e
          warn("YAML syntax error in #{path}: #{e.message}")
          []
        rescue StandardError => e
          warn("Error loading #{path}: #{e.class}: #{e.message.split("\n").first}")
          []
        end

        # Load a spec from a directory structure
        def load_directory_spec(dir, suite: nil)
          template_file = File.join(dir, "template.liquid")
          return unless File.exist?(template_file)

          template = File.read(template_file)
          name = File.basename(dir)

          # Load environment
          env_file = File.join(dir, "environment.yml")
          raw_environment = if File.exist?(env_file)
            safe_load_with_permitted_classes(File.read(env_file)) || {}
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

        private

        def safe_load_with_permitted_classes(content)
          YAML.safe_load(content, permitted_classes: [Symbol, Date, Time, Range], aliases: true)
        end

        # Extract line numbers from YAML AST for each spec
        def extract_line_numbers_from_ast(doc)
          return unless doc&.root

          root = doc.root
          spec_nodes = case root
          when Psych::Nodes::Sequence
            root.children
          when Psych::Nodes::Mapping
            # Check for specs key
            root.children.each_slice(2) do |key, value|
              if key.is_a?(Psych::Nodes::Scalar) && key.value == "specs"
                return value.children if value.is_a?(Psych::Nodes::Sequence)
              end
            end
            []
          else
            []
          end

          # Extract line number from each spec node (Psych uses 0-based, convert to 1-based)
          spec_nodes.map do |node|
            (node.start_line + 1) if node.respond_to?(:start_line)
          end
        end

        # Placeholder - no instantiate processing needed yet
        def process_instantiate_strings(data)
          data
        end
      end
    end
  end
end
