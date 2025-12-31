#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter (strict mode)
#
# Run: liquid-spec adapters/liquid_ruby_strict.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "liquid"
end

LiquidSpec.configure do |config|
  config.suite = :liquid_ruby
  config.error_mode = :strict
end

LiquidSpec.compile do |source, options|
  Liquid::Template.parse(source, line_numbers: true, error_mode: :strict, **options)
end

LiquidSpec.render do |template, ctx|
  liquid_ctx = Liquid::Context.build(
    environments: [ctx.environment],
    registers: Liquid::Registers.new(ctx.registers),
  )
  liquid_ctx.merge(ctx.assigns)
  template.render(liquid_ctx)
end
