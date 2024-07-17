# frozen_string_literal: true

require_relative "liquid_ruby"
require "liquid/c"
require "timeout"

module Liquid
  module Spec
    module Adapter
      class LiquidC < LiquidRuby
        def parse_options
          { line_numbers: true, disable_liquid_c_nodes: false }
        end

        def around_render
          old_enabled = Liquid::C.enabled
          Liquid::C.enabled = true
        ensure
          Liquid::C.enabled = old_enabled
        end
      end
    end
  end
end
