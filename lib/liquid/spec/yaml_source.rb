module Liquid
  module Spec
    class YamlSource < Source
      private

      def specs
        @specs ||= YAML.unsafe_load(spec_data).map do |data|
          Unit.new(
            name: data["name"],
            expected: data["expected"],
            template: data["template"],
            environment: data["environment"] || {},
            filesystem: data["filesystem"],
            error_mode: data["error_mode"],
          )
        end
      end
    end
  end
end
