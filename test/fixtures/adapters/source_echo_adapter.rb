#!/usr/bin/env ruby
# frozen_string_literal: true

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  # The runner loads liquid-ruby fixture classes for some specs. Minimal Ruby
  # adapters should still make Liquid::Drop available even if they do not use
  # liquid-ruby for rendering.
  require "liquid"
end

LiquidSpec.configure do |config|
  config.suite = :basics
  config.missing_features = [
    :runtime_drops,
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

LiquidSpec.compile do |ctx, source, _parse_options|
  ctx[:source] = source
end

LiquidSpec.render do |ctx, _assigns, _render_options|
  ctx[:source]
end
