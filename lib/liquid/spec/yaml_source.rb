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
              if value.keys - %w[TPL EXP CTX FSS generates_ruby_warning] != []
                raise "Unknown keys: #{value.keys} at #{context.join("/")}"
              end
            end

            if expected.is_a?(Hash) && expected.keys.sort == %w[lax strict]
              lax_expected = expected.fetch("lax")
              strict_expected = expected.fetch("strict")
            else
              lax_expected = expected
              strict_expected = expected
            end

            if lax_expected.is_a?(Hash)
              if lax_expected == {'fatal' => true}
                lax_expected = Unit::FATAL
              else
                raise "Invalid lax expected: #{lax_expected} at #{context.join("/")}"
              end
            end

            if strict_expected.is_a?(Hash)
              if strict_expected == {'fatal' => true}
                strict_expected = Unit::FATAL
              else
                raise "Invalid strict expected: #{strict_expected} at #{context.join("/")}"
              end
            end

            trailer = has_multiple ? " (#{index + 1}/#{data.children.size})" : ""

            # TestThing mutates so we need to clone. We could also change TestThing
            env1 = value["CTX"] || {}
            env2 = node.to_ruby["CTX"] || {}

            fixed_args = {
              template: template,
              filesystem: value["FSS"],
              file: spec_path,
              line: node.start_line,
              generates_ruby_warning: value["generates_ruby_warning"],
              context_klass: value["context_klass"].nil? ? Liquid::Context : Object.const_get(value["context_klass"])
            }

            ret << Unit.new(
              name: "[lax] #{context.join(" ")}#{trailer}",
              environment: env1,
              expected: lax_expected,
              error_mode: :lax,
              **fixed_args,
            )

            ret << Unit.new(
              name: "[strict] #{context.join(" ")}#{trailer}",
              environment: env2,
              expected: strict_expected,
              error_mode: :strict,
              **fixed_args,
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
