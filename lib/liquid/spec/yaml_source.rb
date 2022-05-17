module Liquid
  module Spec
    class YamlSource < Source
      private

      def specs
        @specs ||= YAML.unsafe_load(spec_data)
      end
    end
  end
end
