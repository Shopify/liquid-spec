# frozen_string_literal: true

require_relative "liquid_ruby"

module Liquid
  module Spec
    module Adapter
      # Adapter that runs specs using compiled templates with Ruby::Box
      class LiquidRubyCompiled < LiquidRuby
        def render_liquid_template(template, context)
          compiled = template.compile_to_ruby
          compiled.render(context)
        end
      end
    end
  end
end
