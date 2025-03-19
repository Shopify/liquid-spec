# frozen_string_literal: true

require_relative "default"

module Liquid
  module Spec
    module Adapter
      class LiquidRuby < Default
        TEST_TIME = Time.utc(2024, 0o1, 0o1, 0, 1, 58).freeze

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

        def around_render_liquid_template(&block)
          Timecop.freeze(TEST_TIME, &block)
        end

        def render(spec)
          around_render do
            opts = parse_options.merge(error_mode: spec.error_mode&.to_sym).compact
            template = Liquid::Template.parse(spec.template, opts)
            template.name = spec.template_name
            context = spec.context || build_liquid_context(spec)
            context.exception_renderer = spec.exception_renderer
            rendered = around_render_liquid_template do
              render_liquid_template(template, context)
            end
            [rendered, context]
          end
        end

        def render_liquid_template(template, context)
          template.render(context)
        end
      end
    end
  end
end
