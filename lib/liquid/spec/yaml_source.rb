# frozen_string_literal: true

module Liquid
  module Spec
    class YamlSource < Source
      # Global hint for all specs in this source file
      def hint
        metadata["hint"]
      end

      # Required options that adapters must support to run these specs
      # e.g., { error_mode: :lax }
      def required_options
        @required_options ||= (metadata["required_options"] || {}).transform_keys(&:to_sym)
      end

      private

      def parsed_yaml
        @parsed_yaml ||= YAML.unsafe_load(spec_data)
      end

      def metadata
        @metadata ||= if parsed_yaml.is_a?(Hash) && parsed_yaml.key?("_metadata")
          parsed_yaml["_metadata"] || {}
        else
          {}
        end
      end

      def spec_list
        @spec_list ||= if parsed_yaml.is_a?(Hash) && parsed_yaml.key?("specs")
          parsed_yaml["specs"] || []
        elsif parsed_yaml.is_a?(Array)
          parsed_yaml
        else
          []
        end
      end

      def specs
        @specs ||= spec_list.map do |data|
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
            shop_features: data["shop_features"],
            render_errors: data["render_errors"],
            hint: data["hint"],
            source_hint: effective_hint,
            source_required_options: effective_defaults,
            complexity: data["complexity"],
            required_features: data["required_features"] || [],
          )
        end
      end
    end
  end
end
