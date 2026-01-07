#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter with ActiveSupport (lax mode, no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby_lax_activesupport.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do |ctx|
  begin
    require "active_support/all"
  rescue LoadError
    LiquidSpec.skip!("active_support not installed")
  end
  require "liquid"

  # Disable liquid-c if present
  if defined?(Liquid::C) && Liquid::C.respond_to?(:enabled=)
    Liquid::C.enabled = false
  end
end

LiquidSpec.configure do |config|
  config.features = [:core, :lax_parsing, :activesupport]
end

LiquidSpec.compile do |ctx, source, parse_options|
  # Force lax mode regardless of spec (override comes after splat)
  ctx[:template] = Liquid::Template.parse(source, **parse_options, error_mode: :lax)
end

LiquidSpec.render do |ctx, assigns, render_options|
  # Build context with static_environments (read-only assigns that can be shadowed)
  context = Liquid::Context.build(
    static_environments: assigns,
    registers: Liquid::Registers.new(render_options[:registers] || {}),
    rethrow_errors: render_options[:strict_errors],
  )
  context.exception_renderer = render_options[:exception_renderer] if render_options[:exception_renderer]

  ctx[:template].render(context)
end
