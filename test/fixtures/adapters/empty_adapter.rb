#!/usr/bin/env ruby
# frozen_string_literal: true

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup { require "liquid" }

LiquidSpec.configure do |config|
  config.suite = :basics
  config.missing_features = [
    :drops,
    :inline_errors,
    :lax_parsing,
    :ruby_types,
    :ruby_drops,
    :binary_data,
    :template_factory,
    :shopify_tags,
    :shopify_objects,
    :shopify_filters,
  ]
end

LiquidSpec.compile { |ctx, source, _parse_options| ctx[:source] = source }
LiquidSpec.render { |_ctx, _assigns, _render_options| "" }
