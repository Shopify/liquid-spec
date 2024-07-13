# frozen_string_literal: true

module Liquid
  module Spec
    module Adapter
      class LiquidRuby
        def render(spec)
          template = Liquid::Template.parse(spec.template, error_mode: spec.error_mode&.to_sym, line_numbers: true)
          template.name = spec.template_name
          spec.exception_renderer ||= StubExceptionRenderer.new
          context = spec.context || build_liquid_context(spec)
          context.exception_renderer = spec.exception_renderer
          rendered = render_liquid_template(template, context)
          [rendered, context]
        end

        def build_liquid_context(spec)
          static_registers = {
            file_system: StubFileSystem.new(spec.filesystem),
            template_factory: spec.template_factory,
          }
          context = spec.context_klass.build(
            static_environments: Marshal.load(Marshal.dump(spec.environment)),
            registers: Liquid::Registers.new(static_registers),
            rethrow_errors: !spec.render_errors,
          )
          context
        end

        def render_liquid_template(template, context)
          template.render(context)
        end
      end
    end
  end
end
