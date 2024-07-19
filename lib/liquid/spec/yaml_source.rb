# frozen_string_literal: true

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
            context_klass: data["context_klass"].nil? ? Liquid::Context : data["context_klass"],
            template_factory: data["template_factory"],
            template_name: data["template_name"],
            request: data["request"],
            exception_renderer: data["exception_renderer"],
          )
        end
      end
    end
  end
end
