#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid with liquid-c extension (strict mode)
#
# Run: liquid-spec examples/liquid_c_strict.rb
#
# Requires: gem install liquid-c
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do |ctx|
  require "liquid"
  begin
    require "liquid/c"
  rescue LoadError
    LiquidSpec.skip!("liquid-c not installed")
  end

  LiquidSpec.skip!("liquid-c not available") unless defined?(Liquid::C)
  LiquidSpec.skip!("liquid-c not enabled") unless Liquid::C.enabled
end

LiquidSpec.configure do |config|
  config.features = [:core, :strict_parsing]
end

LiquidSpec.compile do |ctx, source, parse_options|
  # Force strict mode regardless of spec (override comes after splat)
  ctx[:template] = Liquid::Template.parse(source, **parse_options, error_mode: :strict)
end

LiquidSpec.render do |ctx, assigns, render_options|
  context = Liquid::Context.build(
    static_environments: assigns,
    registers: Liquid::Registers.new(render_options[:registers] || {}),
    rethrow_errors: render_options[:strict_errors],
  )
  context.exception_renderer = render_options[:exception_renderer] if render_options[:exception_renderer]

  ctx[:template].render(context)
end
