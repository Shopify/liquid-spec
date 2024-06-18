module Liquid
  module Spec
    Unit = Struct.new(
      :name,
      :expected,
      :template,
      :environment,
      :filesystem,
      :error_mode,
      :context_klass,
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
