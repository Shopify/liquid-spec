#!/usr/bin/env ruby
# frozen_string_literal: true

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup { require "liquid" }

LiquidSpec.configure do |config|
  config.suite = :basics
  config.missing_features = [:drops, :inline_errors, :lax_parsing]
end

LiquidSpec.compile { |_ctx, _source, _parse_options| raise SyntaxError, "dumb compile boom" }
LiquidSpec.render { |_ctx, _assigns, _render_options| "unreachable" }
