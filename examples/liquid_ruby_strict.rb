#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter (strict mode, no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby_strict.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "liquid"

  # Disable liquid-c if present
  if defined?(Liquid::C)
    Liquid::C.enabled = false
  end
end

LiquidSpec.configure do |config|
  # Only core feature - no lax_parsing support
  config.features = [:core]
end

LiquidSpec.compile do |source, options|
  # Force strict mode regardless of spec
  Liquid::Template.parse(source, line_numbers: true, error_mode: :strict, disable_liquid_c_nodes: true, **options)
end

LiquidSpec.render do |template, ctx|
  liquid_ctx = ctx.context_klass.build(
    static_environments: ctx.environment,
    registers: Liquid::Registers.new(ctx.registers),
    rethrow_errors: ctx.rethrow_errors?,
  )
  liquid_ctx.exception_renderer = ctx.exception_renderer

  template.render(liquid_ctx)
end
