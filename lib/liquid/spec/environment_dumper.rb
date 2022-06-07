module Liquid
  module Spec
    # Dump Liquid context.environments to plain YAML, expanding all calls to drop methods.
    class EnvironmentDumper
      def initialize(context)
        @context = context
      end

      def to_yaml
        dump = {}
        @context.environments.reverse.each do |env|
          env.each do |name, value|
            dump[name] = dump_liquid_value(value, nested_level: 0)
          end
        end
        dump.to_yaml
      end

      private

      def dump_liquid_value(value, nested_level:)
        return nil if nested_level > 5
        case value
        when Liquid::Drop
          dump_liquid_drop(value, nested_level: nested_level + 1)
        when Proc
          if value.arity == 1
            v = value.call(@context)
          else
            v = value.call
          end
          dump_liquid_value(v, nested_level: nested_level + 1)
        when Array
          value.map { |v| dump_liquid_value(v, nested_level: nested_level + 1) }
        when Struct
          value.members.each_with_object({}) do |hash, key|
            hash[key] = dump_liquid_value(value[key], nested_level: nested_level + 1)
          end
        when Hash
          value.each_with_object({}) do |hash, (key, v)|
            hash[key] = dump_liquid_value(v, nested_level: nested_level + 1)
          end
        when ActiveSupport::TimeWithZone
          value.to_s
        else
          value.to_liquid
        end
      end
  
      def dump_liquid_drop(drop, nested_level:)
        drop.class.invokable_methods.each_with_object({}) do |method, dump|
          drop.context = @context if drop.respond_to?(:context=)
          if method != "to_liquid" && drop.method(method).arity == 0
            dump[method] = begin
              dump_liquid_value(drop.invoke_drop(method), nested_level: nested_level + 1)
            rescue => e
              nil
            end
          end
        end
      end
    end
  end
end
