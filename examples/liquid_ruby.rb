#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter (lax mode)
#
# Run: liquid-spec adapters/liquid_ruby.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "liquid"
end

LiquidSpec.configure do |config|
  config.suite = :liquid_ruby
  config.error_mode = :lax
end

LiquidSpec.compile do |source, options|
  Liquid::Template.parse(source, line_numbers: true, **options)
end

LiquidSpec.render do |template, ctx|
  registers = Liquid::Registers.new(ctx.registers)
  registers[:template_factory] = ctx.template_factory if ctx.template_factory

  liquid_ctx = Liquid::Context.build(
    environments: [ctx.environment],
    registers: registers,
    rethrow_errors: false,
  )
  liquid_ctx.merge(ctx.assigns)
  liquid_ctx.exception_renderer = ctx.exception_renderer if ctx.exception_renderer

  template.render(liquid_ctx)
end
