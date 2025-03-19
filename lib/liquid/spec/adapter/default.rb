# frozen_string_literal: true

module Liquid
  module Spec
    module Adapter
      class Default
        def render(spec)
          spec.expected || raise("no expected value")

          [spec.expected, build_liquid_context(spec)]
        end

        def build_liquid_context(spec)
          fs = case spec.filesystem
          when Hash
            StubFileSystem.new(spec.filesystem)
          when nil
            StubFileSystem.new({})
          else
            spec.filesystem
          end

          static_registers = {
            file_system: fs,
            template_factory: spec.template_factory,
          }
          context = spec.context_klass.build(
            static_environments: Marshal.load(Marshal.dump(spec.environment)),
            registers: Liquid::Registers.new(static_registers),
            rethrow_errors: !spec.render_errors,
          )
          context
        end
      end
    end
  end
end
