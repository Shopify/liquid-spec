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
      :file,
      :line,
      :generates_ruby_warning,
      keyword_init: true
    ) do
      def initialize(**)
        super
        self.environment ||= {}
        self.filesystem ||= {}
      end
    end
    Unit::FATAL = :fatal
  end
end
