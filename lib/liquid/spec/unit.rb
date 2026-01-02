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
      keyword_init: true,
    ) do
      def initialize(**orig)
        super
        self.environment ||= {}
        self.filesystem ||= {}
        self.exception_renderer ||= StubExceptionRenderer.new
        self.source_required_options ||= {}
        self.required_features ||= []
        self.orig = orig.transform_keys(&:to_s)
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
      def effective_hint
        hint || source_hint
      end
    end
  end
end
