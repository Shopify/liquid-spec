#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter (pure Ruby, no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "active_support/all"
  require "liquid"

  # Disable liquid-c if present
  if defined?(Liquid::C)
    Liquid::C.enabled = false
  end
end

LiquidSpec.configure do |config|
  # Declare which features this Liquid implementation supports
  config.features = [
    :core,        # Basic Liquid parsing and rendering
    :lax_parsing, # Supports error_mode: :lax
  ]
end

LiquidSpec.compile do |source, options|
  Liquid::Template.parse(source, line_numbers: true, disable_liquid_c_nodes: true, **options)
end

LiquidSpec.render do |template, ctx|
  liquid_ctx = ctx.context_klass.build(
    static_environments: ctx.environment,
    registers: Liquid::Registers.new(ctx.registers),
    rethrow_errors: ctx.rethrow_errors?,
  )
  # Only set exception_renderer if provided (otherwise keep default)
  liquid_ctx.exception_renderer = ctx.exception_renderer if ctx.exception_renderer

  template.render(liquid_ctx)
end
