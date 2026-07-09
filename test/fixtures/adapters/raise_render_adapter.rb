#!/usr/bin/env ruby
# frozen_string_literal: true

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup { require "liquid" }

LiquidSpec.configure do |config|
  config.suite = :basics
  config.missing_features = [:drops, :inline_errors, :lax_parsing]
end

LiquidSpec.compile { |ctx, source, _parse_options| ctx[:source] = source }
LiquidSpec.render { |_ctx, _assigns, _render_options| raise RuntimeError, "dumb render boom" }
