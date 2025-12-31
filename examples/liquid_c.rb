#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid with liquid-c extension
#
# Run: liquid-spec adapters/liquid_c.rb
#
# Requires: gem install liquid-c
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "liquid"
  require "liquid/c"

  unless defined?(Liquid::C) && Liquid::C.enabled
    abort "liquid-c is not available. Install with: gem install liquid-c"
  end
end

LiquidSpec.configure do |config|
  config.suite = :liquid_ruby
  config.error_mode = :lax
end

LiquidSpec.compile do |source, options|
  Liquid::Template.parse(source, line_numbers: true, **options)
end

LiquidSpec.render do |template, ctx|
  liquid_ctx = Liquid::Context.build(
    environments: [ctx.environment],
    registers: Liquid::Registers.new(ctx.registers),
  )
  liquid_ctx.merge(ctx.assigns)
  template.render(liquid_ctx)
end
