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
      keyword_init: true,
    ) do
      def initialize(**orig)
        super
        self.environment ||= {}
        self.filesystem ||= {}
        self.exception_renderer ||= StubExceptionRenderer.new
        self.source_required_options ||= {}
        self.orig = orig.transform_keys(&:to_s)
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
