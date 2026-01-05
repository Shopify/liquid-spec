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
  config.features = [:core, :lax_parsing]
end

LiquidSpec.compile do |ctx, source, options|
  # Force lax mode regardless of spec (override comes after splat)
  Liquid::Template.parse(source, **options, error_mode: :lax)
end

LiquidSpec.render do |ctx, template, assigns, options|
  context = Liquid::Context.build(
    static_environments: assigns,
    registers: Liquid::Registers.new(options[:registers] || {}),
    rethrow_errors: options[:strict_errors],
  )
  context.exception_renderer = options[:exception_renderer] if options[:exception_renderer]

  template.render(context)
end
