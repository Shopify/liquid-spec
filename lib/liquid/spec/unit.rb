# frozen_string_literal: true

module Liquid
  module Spec
    Unit = Struct.new(
      :name,
      :expected,
      :template,
      :template_name,
      :environment,
      :filesystem,
      :error_mode,
      :context_klass,
      :template_factory,
      :render_errors,
      :message,
      :exception_renderer,
      :request,
      :context,
      :orig,
      :shop_features,
      :hint,
      :source_hint,
      :source_required_options,
      :complexity,
      :required_features,
      :errors,
      :doc,
      keyword_init: true,
    ) do
      def initialize(**orig)
        super
        self.environment ||= {}
        self.filesystem ||= {}
        self.exception_renderer ||= StubExceptionRenderer.new
        self.source_required_options ||= {}
        self.required_features ||= []
        self.errors ||= {}
        self.orig = orig.transform_keys(&:to_s)
      end

      # Check if this spec expects a parse error
      def expects_parse_error?
        errors.key?("parse_error") || errors.key?(:parse_error)
      end

      # Check if this spec expects a render error (exception during render)
      def expects_render_error?
        errors.key?("render_error") || errors.key?(:render_error)
      end

      # Check if this spec expects output to match patterns (instead of exact match)
      def expects_output_patterns?
        errors.key?("output") || errors.key?(:output)
      end

      # Get patterns for a specific error type
      def error_patterns(type)
        patterns = errors[type.to_s] || errors[type.to_sym] || []
        Array(patterns).map { |p| p.is_a?(Regexp) ? p : Regexp.new(p.to_s) }
      end

      # Check if this spec can run with the given features
      def runnable_with?(features)
        return true if required_features.empty?

        features_set = features.map(&:to_sym).to_set
        required_features.all? { |f| features_set.include?(f.to_sym) }
      end

      # List of missing features
      def missing_features(features)
        features_set = features.map(&:to_sym).to_set
        required_features.map(&:to_sym).reject { |f| features_set.include?(f) }
      end

      def context_klass
        self[:context_klass] || Liquid::Context
      end

      # Returns the effective hint (spec-level hint takes precedence over source-level)
      # If a doc is specified, appends the doc path to the hint
      def effective_hint
        base_hint = hint || source_hint
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

      # Resolve the doc path relative to liquid-spec/docs
      def resolve_doc_path
        return unless doc

        # Find liquid-spec root (where docs/ lives)
        # __dir__ is lib/liquid/spec, so go up 3 levels to liquid-spec
        spec_root = File.expand_path("../../..", __dir__)
        doc_file = File.join(spec_root, "docs", doc)

        if File.exist?(doc_file)
          doc_file
        else
          # Try without docs/ prefix in case it's already a full path
          alt_path = File.join(spec_root, doc)
          File.exist?(alt_path) ? alt_path : nil
        end
      end
    end
  end
end
