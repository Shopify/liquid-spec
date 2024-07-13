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
      keyword_init: true,
    ) do
      def initialize(**)
        super
        self.environment ||= {}
        self.filesystem ||= {}
      end

      def context_klass
        self[:context_klass] || Liquid::Context
      end
    end
  end
end
