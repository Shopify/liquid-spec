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
            context_klass: data["context_klass"].nil? ? Liquid::Context : Object.const_get(data["context_klass"])
          )
        end
      end
    end
  end
end
