#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter (lax mode, no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby_lax.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "liquid"

  # Disable liquid-c if present
  if defined?(Liquid::C) && Liquid::C.respond_to?(:enabled=)
    Liquid::C.enabled = false
  end
end

LiquidSpec.configure do |config|
  config.features = [:core, :lax_parsing]
end

LiquidSpec.compile do |source, options|
  # Force lax mode regardless of spec (override comes after splat)
  Liquid::Template.parse(source, **options, error_mode: :lax)
end

LiquidSpec.render do |template, assigns, options|
  # Build context with static_environments (read-only assigns that can be shadowed)
  context = Liquid::Context.build(
    static_environments: assigns,
    registers: Liquid::Registers.new(options[:registers] || {}),
    rethrow_errors: options[:strict_errors],
  )
  context.exception_renderer = options[:exception_renderer] if options[:exception_renderer]

  template.render(context)
end
