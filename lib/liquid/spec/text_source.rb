module Liquid
  module Spec
    class TextSource < Source
      private

      def specs
        @specs ||= []
      end
    end
  end
end
