# frozen_string_literal: true

module Liquid
  module Spec
    module Adapter
      class LiquidRuby
        def parse_options
          { line_numbers: true, disable_liquid_c_nodes: true }
        end

        def around_render
          old_enabled = Liquid::C.enabled if defined?(Liquid::C)
          Liquid::C.enabled = false if defined?(Liquid::C)
          yield
        ensure
          Liquid::C.enabled = old_enabled if defined?(Liquid::C)
        end

        def around_render_liquid_template
          yield
        end

        def render(spec)
          around_render do
            opts = parse_options.merge(error_mode: spec.error_mode&.to_sym).compact
            template = Liquid::Template.parse(spec.template, opts)
            template.name = spec.template_name
            spec.exception_renderer ||= StubExceptionRenderer.new
            context = spec.context || build_liquid_context(spec)
            context.exception_renderer = spec.exception_renderer
            rendered = around_render_liquid_template do
              render_liquid_template(template, context)
            end
            [rendered, context]
          end
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
