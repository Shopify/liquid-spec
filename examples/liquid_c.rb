#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid with liquid-c extension
#
# Run: liquid-spec examples/liquid_c.rb
#
# Requires: gem install liquid-c
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "liquid"
  require "liquid/c"

  raise "liquid-c is not available. Install with: gem install liquid-c" unless defined?(Liquid::C)
  raise "liquid-c is not enabled" unless Liquid::C.enabled
end

LiquidSpec.configure do |config|
  # liquid-c supports both core and lax parsing
  config.features = [:core, :lax_parsing]
end

LiquidSpec.compile do |source, options|
  Liquid::Template.parse(source, line_numbers: true, **options)
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
