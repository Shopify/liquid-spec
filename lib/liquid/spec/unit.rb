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
      :request,
      :render_errors,
      :message,
      keyword_init: true
    ) do
      def initialize(**)
        super
        self.environment ||= {}
        self.filesystem ||= {}
      end
    end
  end
end
