# frozen_string_literal: true

require "yaml"
require_relative "spec_loader"

module Liquid
  module Spec
    # Error raised when a spec fails validation
    class SpecValidationError < StandardError
      attr_reader :spec_name, :source_file, :line_number, :errors

      def initialize(spec_name:, source_file:, line_number:, errors:)
        @spec_name = spec_name
        @source_file = source_file
        @line_number = line_number
        @errors = errors

        location = source_file
        location = "#{location}:#{line_number}" if line_number
        message = "Invalid spec '#{spec_name}' at #{location}:\n"
        errors.each { |e| message += "  - #{e}\n" }
        super(message)
      end
    end

    # A lazy spec that delays drop instantiation until render time
    # Environment data may be stored as a YAML string for deferred instantiation
    class LazySpec
      VALID_ERROR_KEYS = ["parse_error", "render_error", "output"].freeze

      attr_reader :name, :template, :expected, :errors, :hint, :doc, :complexity
      attr_reader :error_mode, :render_errors, :required_features
      attr_reader :source_file, :line_number
      attr_reader :raw_environment, :raw_filesystem, :raw_template_factory

      def initialize(
        name:,
        template:,
        expected: nil,
        errors: {},
        hint: nil,
        doc: nil,
        complexity: 1000,
        error_mode: nil,
        render_errors: false,
        required_features: [],
        source_file: nil,
        line_number: nil,
        raw_environment: {},
        raw_filesystem: {},
        raw_template_factory: nil,
        source_hint: nil,
        source_required_options: {}
      )
        @name = name
        @template = template
        @expected = expected
        @errors = errors || {}
        @hint = hint
        @doc = doc
        @complexity = complexity
        @error_mode = error_mode || source_required_options[:error_mode]
        @render_errors = render_errors
        @required_features = Array(required_features).map(&:to_sym)
        @source_file = source_file
        @line_number = line_number
        @raw_environment = raw_environment || {}
        @raw_filesystem = raw_filesystem || {}
        @raw_template_factory = raw_template_factory
        @source_hint = source_hint
        @source_required_options = source_required_options || {}

        # Add parsing mode requirement based on error_mode
        if @error_mode == :lax && !@required_features.include?(:lax_parsing)
          @required_features << :lax_parsing
        elsif @error_mode == :strict && !@required_features.include?(:strict_parsing)
          @required_features << :strict_parsing
        end
      end

      # Location string for error messages
      def location
        if source_file && line_number
          "#{source_file}:#{line_number}"
        elsif source_file
          source_file
        else
          name
        end
      end

      # Check if this spec requires a specific feature
      def requires_feature?(feature)
        required_features.include?(feature.to_sym)
      end

      # Check if spec can run with given features
      def runnable_with?(features)
        feature_set = features.is_a?(Set) ? features : Set.new(features.map(&:to_sym))
        required_features.all? { |f| feature_set.include?(f) }
      end

      # List of missing features
      def missing_features(features)
        features_set = features.map(&:to_sym).to_set
        required_features.reject { |f| features_set.include?(f) }
      end

      # Check if this spec expects a parse error
      def expects_parse_error?
        errors.key?("parse_error") || errors.key?(:parse_error)
      end

      # Check if this spec expects a render error
      def expects_render_error?
        errors.key?("render_error") || errors.key?(:render_error)
      end

      # Check if this spec expects output to match patterns
      def expects_output_patterns?
        errors.key?("output") || errors.key?(:output)
      end

      # Get patterns for a specific error type
      def error_patterns(type)
        patterns = errors[type.to_s] || errors[type.to_sym] || []
        Array(patterns).map { |p| p.is_a?(Regexp) ? p : Regexp.new(p.to_s, Regexp::IGNORECASE) }
      end

      # Returns the effective hint (spec-level hint takes precedence over source-level)
      def effective_hint
        base_hint = @hint || @source_hint
        return base_hint unless doc

        doc_path = resolve_doc_path
        if doc_path && base_hint
          "#{base_hint.chomp}\n\nSee: #{doc_path}"
        elsif doc_path
          "See: #{doc_path}"
        else
          base_hint
        end
      end

      # Returns source-level required options
      attr_reader :source_required_options

      # Validate the spec and raise SpecValidationError if invalid
      def validate!
        validation_errors = []

        # Rule 1: Must have name
        if name.nil? || name.to_s.strip.empty?
          validation_errors << "missing required field 'name'"
        end

        # Rule 2: Must have template (can be empty string, but not nil)
        if template.nil?
          validation_errors << "missing required field 'template'"
        end

        # Rule 3: Must have either expected or errors
        if expected.nil? && (errors.nil? || errors.empty?)
          validation_errors << "must have either 'expected' or 'errors' (got neither)"
        end

        # Rule 4: Check for unknown error keys
        if errors && !errors.empty?
          error_keys = errors.keys.map(&:to_s)
          unknown_keys = error_keys - VALID_ERROR_KEYS
          if unknown_keys.any?
            validation_errors << "unknown error type(s): #{unknown_keys.join(", ")} (valid: #{VALID_ERROR_KEYS.join(", ")})"
          end
        end

        # Rule 5: render_errors: true should only have output errors, not thrown errors
        if render_errors && errors && !errors.empty?
          has_thrown_errors = errors.key?("parse_error") || errors.key?(:parse_error) ||
            errors.key?("render_error") || errors.key?(:render_error)
          if has_thrown_errors
            validation_errors << "render_errors: true but has parse_error/render_error (use errors.output for rendered errors)"
          end
        end

        # Rule 6: render_errors: false (or not set) should not have output errors
        if !render_errors && errors && !errors.empty?
          has_output_errors = errors.key?("output") || errors.key?(:output)
          if has_output_errors
            validation_errors << "has errors.output but render_errors is not true (output errors require render_errors: true)"
          end
        end

        # Rule 7: If expected contains "Liquid error", render_errors should be true
        if expected.is_a?(String) && expected =~ /\ALiquid(?: \w+)? error/i && !render_errors
          validation_errors << "expected contains 'Liquid error' but render_errors is not true (error output requires render_errors: true, or use errors.output)"
        end

        # Raise if any validation errors
        if validation_errors.any?
          raise SpecValidationError.new(
            spec_name: name || "(unnamed)",
            source_file: source_file,
            line_number: line_number,
            errors: validation_errors,
          )
        end

        true
      end

      # Check if spec is valid without raising
      def valid?
        validate!
        true
      rescue SpecValidationError
        false
      end

      # Get validation errors without raising
      def validation_errors
        validate!
        []
      rescue SpecValidationError => e
        e.errors
      end

      # Instantiate environment for this spec
      # If raw_environment is a String, parse it as YAML with custom object support
      # If it's already a Hash, instantiate any deferred objects
      def instantiate_environment
        case @raw_environment
        when String
          # YAML string - parse with custom object support
          instantiate_from_yaml(@raw_environment)
        when Hash
          # Already a hash - deep copy and instantiate any deferred objects
          deep_instantiate(@raw_environment)
        else
          {}
        end
      end

      # Instantiate filesystem for this spec
      # Returns an object that responds to read_template_file
      # Filesystem is always a simple hash of filename => content
      def instantiate_filesystem
        return if @raw_filesystem.nil?

        # Filesystem is always a plain hash - no instantiate: patterns
        # Just filename keys mapping to template content strings
        # An empty hash {} means "filesystem exists but has no files" (returns not found errors)
        # nil means "no filesystem" (includes not allowed)
        files = case @raw_filesystem
        when Hash
          # Filter out any non-string values (legacy instantiate: patterns)
          @raw_filesystem.reject { |k, _| k.to_s == "instantiate" }
        else
          {}
        end

        SimpleFileSystem.new(files)
      end

      # Instantiate template_factory for this spec
      def instantiate_template_factory
        return if @raw_template_factory.nil?

        deep_instantiate(@raw_template_factory)
      end

      private

      # Parse YAML string and instantiate custom objects using the registry
      def instantiate_from_yaml(yaml_str)
        return {} if yaml_str.nil? || yaml_str.empty?

        # Use unsafe_load - the classes should be defined by now
        YAML.unsafe_load(yaml_str)
      rescue => e
        warn("Failed to instantiate environment: #{e.message}")
        {}
      end

      # Deep copy a hash and instantiate any deferred objects
      def deep_instantiate(obj, seen = {}.compare_by_identity)
        return seen[obj] if seen.key?(obj)

        case obj
        when Hash
          # Check if this is an instantiate definition (single key starting with "instantiate:")
          if obj.size == 1
            key = obj.keys.first
            value = obj.values.first
            if key.is_a?(String) && key.start_with?("instantiate:")
              class_name = key.sub("instantiate:", "")
              # Deep instantiate the parameters first
              params = deep_instantiate(value, seen)
              # Create a fresh instance via the registry
              instance = ClassRegistry.instantiate(class_name, params)
              return instance if instance
            end
          end

          # Otherwise, do a deep copy
          copy = {}
          seen[obj] = copy
          obj.each do |k, v|
            copy[deep_instantiate(k, seen)] = deep_instantiate(v, seen)
          end
          copy
        when Array
          copy = []
          seen[obj] = copy
          obj.each { |v| copy << deep_instantiate(v, seen) }
          copy
        when String
          # Handle string format: "instantiate:ClassName.new(arg)"
          if obj.start_with?("instantiate:")
            if obj =~ /\Ainstantiate:(\w+)\.new\((.+)\)\z/
              class_name = ::Regexp.last_match(1)
              arg_str = ::Regexp.last_match(2)
              # Parse the argument (handles integers, strings, etc.)
              arg = begin
                Integer(arg_str)
              rescue ArgumentError
                arg_str # Keep as string if not an integer
              end
              instance = ClassRegistry.instantiate(class_name, arg)
              return instance if instance
            end
          end
          obj
        else
          # Already instantiated or primitive
          obj
        end
      end

      # Resolve the doc path relative to liquid-spec/docs
      def resolve_doc_path
        return unless doc

        # Find liquid-spec root (where docs/ lives)
        spec_root = File.expand_path("../../..", __dir__)
        doc_file = File.join(spec_root, "docs", doc)

        if File.exist?(doc_file)
          doc_file
        else
          # Try without docs/ prefix
          alt_path = File.join(spec_root, doc)
          File.exist?(alt_path) ? alt_path : nil
        end
      end

      # Simple filesystem implementation for specs
      class SimpleFileSystem
        attr_reader :templates

        def initialize(templates)
          @templates = (templates || {}).transform_keys do |key|
            key = key.to_s.downcase
            key = "#{key}.liquid" unless key.end_with?(".liquid")
            key
          end
        end

        def read_template_file(template_path)
          original_path = template_path.to_s
          path = original_path.downcase
          path = "#{path}.liquid" unless path.end_with?(".liquid")
          @templates.find { |name, _| name.casecmp?(path) }&.last or
            raise "Could not find template: #{original_path}"
        end

        def to_h
          @templates.dup
        end
      end
    end
  end
end
