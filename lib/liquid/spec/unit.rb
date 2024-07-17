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
      keyword_init: true,
    ) do
      def initialize(**orig)
        super
        self.environment ||= {}
        self.filesystem ||= {}
        self.orig = orig.transform_keys(&:to_s)
      end

      def context_klass
        self[:context_klass] || Liquid::Context
      end
    end
  end
end
