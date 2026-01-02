# frozen_string_literal: true

require "yaml"

module Liquid
  module Spec
    # A lazy spec that delays drop instantiation until render time
    # Environment data may be stored as a YAML string for deferred instantiation
    class LazySpec
      attr_reader :name, :template, :expected, :errors, :hint, :doc, :complexity
      attr_reader :error_mode, :render_errors, :required_features
      attr_reader :source_file, :line_number
      attr_reader :raw_environment, :raw_filesystem

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
        @source_hint = source_hint
        @source_required_options = source_required_options || {}

        # Add lax_parsing requirement if error_mode is lax
        if @error_mode == :lax && !@required_features.include?(:lax_parsing)
          @required_features << :lax_parsing
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
      def instantiate_filesystem
        return if @raw_filesystem.nil? || @raw_filesystem.empty?

        fs = case @raw_filesystem
        when String
          instantiate_from_yaml(@raw_filesystem)
        when Hash
          deep_instantiate(@raw_filesystem)
        else
          {}
        end

        SimpleFileSystem.new(fs)
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
        def initialize(templates)
          @templates = (templates || {}).transform_keys do |key|
            key = key.to_s.downcase
            key = "#{key}.liquid" unless key.end_with?(".liquid")
            key
          end
        end

        def read_template_file(template_path)
          path = template_path.to_s
          path = "#{path}.liquid" unless path.downcase.end_with?(".liquid")
          @templates.find { |name, _| name.casecmp?(path) }&.last or
            raise Liquid::FileSystemError, "Could not find asset #{path}"
        end
      end
    end
  end
end
