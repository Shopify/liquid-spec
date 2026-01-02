# frozen_string_literal: true

require "yaml"
require_relative "lazy_spec"

module Liquid
  module Spec
    # Registry for custom YAML classes used in specs
    # Maps class name strings to actual Class objects
    module ClassRegistry
      @classes = {}

      class << self
        def register(name, klass)
          @classes[name] = klass
        end

        def lookup(name)
          @classes[name]
        end

        def registered?(name)
          @classes.key?(name)
        end

        def all
          @classes.dup
        end

        def clear!
          @classes.clear
        end
      end
    end

    # Loads specs from YAML files without instantiating drop objects
    module SpecLoader
      class << self
        # Ensure test infrastructure is loaded
        def ensure_test_infrastructure!
          return if @infrastructure_loaded

          # Load test drops and register them
          if defined?(Liquid::Template)
            require_relative "deps/liquid_ruby"
            register_test_classes!
          end

          @infrastructure_loaded = true
        end

        # Register all test classes in the registry
        def register_test_classes!
          # Core test classes
          ClassRegistry.register("TestThing", TestThing) if defined?(TestThing)
          ClassRegistry.register("TestDrop", TestDrop) if defined?(TestDrop)
          ClassRegistry.register("TestEnumerable", TestEnumerable) if defined?(TestEnumerable)
          ClassRegistry.register("NumberLikeThing", NumberLikeThing) if defined?(NumberLikeThing)
          ClassRegistry.register("ThingWithToLiquid", ThingWithToLiquid) if defined?(ThingWithToLiquid)
          ClassRegistry.register("ThingWithValue", ThingWithValue) if defined?(ThingWithValue)
          ClassRegistry.register("BooleanDrop", BooleanDrop) if defined?(BooleanDrop)
          ClassRegistry.register("IntegerDrop", IntegerDrop) if defined?(IntegerDrop)
          ClassRegistry.register("StringDrop", StringDrop) if defined?(StringDrop)
          ClassRegistry.register("ErrorDrop", ErrorDrop) if defined?(ErrorDrop)
          ClassRegistry.register("SettingsDrop", SettingsDrop) if defined?(SettingsDrop)
          ClassRegistry.register("CustomToLiquidDrop", CustomToLiquidDrop) if defined?(CustomToLiquidDrop)
          ClassRegistry.register("HashWithCustomToS", HashWithCustomToS) if defined?(HashWithCustomToS)
          ClassRegistry.register("HashWithoutCustomToS", HashWithoutCustomToS) if defined?(HashWithoutCustomToS)
          ClassRegistry.register("StubFileSystem", StubFileSystem) if defined?(StubFileSystem)
          ClassRegistry.register("StubTemplateFactory", StubTemplateFactory) if defined?(StubTemplateFactory)
          ClassRegistry.register("StubExceptionRenderer", StubExceptionRenderer) if defined?(StubExceptionRenderer)

          # Nested classes
          ClassRegistry.register("ForTagTest::LoaderDrop", ForTagTest::LoaderDrop) if defined?(ForTagTest::LoaderDrop)
          ClassRegistry.register("TableRowTest::ArrayDrop", TableRowTest::ArrayDrop) if defined?(TableRowTest::ArrayDrop)
        end

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

          # Check if file contains custom Ruby objects
          has_custom_objects = content.include?("!ruby/")

          if has_custom_objects
            # Ensure test classes are loaded before parsing
            ensure_test_infrastructure!
            # Use unsafe_load to instantiate custom objects
            data = YAML.unsafe_load(content)
          else
            # No custom objects - safe to load normally
            data = safe_load_with_permitted_classes(content)
          end
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

            # Keep environment as-is (may contain tagged objects or plain data)
            raw_env = spec_data["environment"] || {}

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
              raw_environment: raw_env,
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
        rescue Psych::DisallowedClass
          # File contains custom classes we can't safe_load
          # Fall back to loading with custom class handler
          load_yaml_file_with_deferred_objects(path, suite: suite)
        rescue StandardError => e
          warn("Error loading #{path}: #{e.class}: #{e.message.split("\n").first}")
          []
        end

        # Load YAML file that contains custom objects, deferring their instantiation
        def load_yaml_file_with_deferred_objects(path, suite: nil)
          content = File.read(path)
          specs = []

          # Parse YAML into AST without instantiating objects
          doc = Psych.parse(content)
          return specs unless doc

          root = doc.root
          return specs unless root

          # Extract specs from the AST
          spec_nodes = extract_spec_nodes(root)

          # Suite/metadata defaults
          suite_defaults = suite&.defaults || {}
          default_render_errors = suite_defaults[:render_errors]
          minimum_complexity = suite&.minimum_complexity || 1000

          spec_nodes.each do |spec_node|
            spec_data = extract_spec_data(spec_node)
            next unless spec_data

            # Determine render_errors
            spec_render_errors = if spec_data.key?(:render_errors)
              spec_data[:render_errors]
            else
              default_render_errors
            end

            # Extract the environment node as YAML string for deferred loading
            env_yaml = extract_environment_yaml(spec_node)

            spec = LazySpec.new(
              name: spec_data[:name],
              template: spec_data[:template],
              expected: spec_data[:expected],
              errors: spec_data[:errors] || {},
              hint: spec_data[:hint],
              complexity: spec_data[:complexity] || minimum_complexity,
              error_mode: spec_data[:error_mode]&.to_sym,
              render_errors: spec_render_errors || false,
              required_features: spec_data[:required_features] || [],
              source_file: path,
              line_number: spec_node.start_line,
              raw_environment: env_yaml, # Store as YAML string
              raw_filesystem: spec_data[:filesystem] || {},
              source_hint: nil,
              source_required_options: {},
            )

            specs << spec
          end

          specs
        rescue => e
          warn("Error loading #{path}: #{e.class}: #{e.message.split("\n").first}")
          []
        end

        # Load a spec from a directory structure
        def load_directory_spec(dir, suite: nil)
          template_file = File.join(dir, "template.liquid")
          return unless File.exist?(template_file)

          template = File.read(template_file)
          name = File.basename(dir)

          # Load environment - keep as YAML string if it has custom objects
          env_file = File.join(dir, "environment.yml")
          raw_environment = if File.exist?(env_file)
            env_content = File.read(env_file)
            if env_content.include?("!ruby/")
              env_content # Keep as string for deferred loading
            else
              YAML.safe_load(env_content, permitted_classes: [Symbol, Date, Time, Range]) || {}
            end
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
          YAML.safe_load(
            content,
            permitted_classes: [Symbol, Date, Time, Range],
            aliases: true,
          )
        rescue ArgumentError
          # Ruby 4.0 changed the API
          YAML.safe_load(content, permitted_classes: [Symbol, Date, Time, Range])
        end

        # Extract spec nodes from YAML AST
        def extract_spec_nodes(root)
          case root
          when Psych::Nodes::Sequence
            root.children
          when Psych::Nodes::Mapping
            # Check for specs key or _metadata structure
            root.children.each_slice(2) do |key, value|
              if key.is_a?(Psych::Nodes::Scalar) && key.value == "specs"
                return value.children if value.is_a?(Psych::Nodes::Sequence)
              end
            end
            # If no specs key, maybe it's a simple array at root
            []
          else
            []
          end
        end

        # Extract basic spec data from a mapping node (without instantiating objects)
        def extract_spec_data(node)
          return unless node.is_a?(Psych::Nodes::Mapping)

          data = {}
          node.children.each_slice(2) do |key_node, value_node|
            next unless key_node.is_a?(Psych::Nodes::Scalar)

            key = key_node.value.to_sym
            value = safe_extract_value(value_node)
            data[key] = value
          end

          data
        end

        # Safely extract a scalar or simple value from a node
        def safe_extract_value(node)
          case node
          when Psych::Nodes::Scalar
            # Try to parse as appropriate type
            case node.tag
            when "tag:yaml.org,2002:int"
              node.value.to_i
            when "tag:yaml.org,2002:float"
              node.value.to_f
            when "tag:yaml.org,2002:bool"
              node.value.downcase == "true"
            when "tag:yaml.org,2002:null"
              nil
            else
              node.value
            end
          when Psych::Nodes::Sequence
            node.children.map { |child| safe_extract_value(child) }
          when Psych::Nodes::Mapping
            # For mappings that might contain custom objects, return as-is
            # They'll be handled in environment instantiation
            hash = {}
            node.children.each_slice(2) do |k, v|
              if k.is_a?(Psych::Nodes::Scalar)
                hash[k.value] = safe_extract_value(v)
              end
            end
            hash
          end
        end

        # Extract environment as YAML string from spec node
        def extract_environment_yaml(spec_node)
          return {} unless spec_node.is_a?(Psych::Nodes::Mapping)

          spec_node.children.each_slice(2) do |key_node, value_node|
            if key_node.is_a?(Psych::Nodes::Scalar) && key_node.value == "environment"
              # Convert this subtree back to YAML string
              return node_to_yaml_string(value_node)
            end
          end

          {}
        end

        # Convert a Psych node to a YAML string
        def node_to_yaml_string(node)
          stream = Psych::Nodes::Stream.new
          doc = Psych::Nodes::Document.new
          doc.children << node
          stream.children << doc
          stream.to_yaml.sub(/\A---\n?/, "").sub(/\n?\.\.\.\n?\z/, "").strip
        end
      end
    end
  end
end
