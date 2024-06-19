require 'psych'

module Liquid
  module Spec
    class YamlSource < Source
      private

      def toplevel
        stream = Psych.parser.parse(spec_data)
        document = stream.handler.root.children[0]
        document.children[0]
      end

      def specs
        @specs ||= process_specs([], toplevel)
      end

      def process_specs(context, data)
        ret = []

        if data.mapping?
          data.children.each_slice(2).map do |key, value|
            if key.value == 'TPL'
              raise "Invalid nesting at #{context.join("/")}: specs must be wrapped in an array"
            end
            ret.concat(process_specs(context + [key.value], value))
          end
        elsif data.sequence?
          has_multiple = data.children.size > 1
          data.children.each.with_index do |node, index|
            value = node.to_ruby

            template = value["TPL"]
            expected = value["EXP"]
            if value.size == 1
              template = value.keys.first
              expected = value.values.first
            else
              if value.keys - %w[TPL EXP CTX FSS] != []
                raise "Unknown keys: #{value.keys} at #{context.join("/")}"
              end
            end

            trailer = has_multiple ? " (#{index + 1}/#{data.children.size})" : ""
            ret << Unit.new(
              name: "#{context.join(" ")}#{trailer}",
              expected: expected,
              template: template,
              environment: value["CTX"] || {},
              filesystem: value["FSS"],
              file: spec_path,
              line: node.start_line,
              # TODO these are unused?
              error_mode: value["error_mode"],
              context_klass: value["context_klass"].nil? ? Liquid::Context : Object.const_get(value["context_klass"])
            )
          end
        else
          raise "Unknown data type: #{data} at #{context.join("/")}"
        end

        ret
      end
    end
  end
end
