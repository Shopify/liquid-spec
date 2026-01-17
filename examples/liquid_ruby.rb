#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter (pure Ruby, no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do |ctx|
  require "liquid"

  # Disable liquid-c if present
  if defined?(Liquid::C) && Liquid::C.respond_to?(:enabled=)
    Liquid::C.enabled = false
  end
end

LiquidSpec.configure do |config|
  config.features = [:core, :strict_parsing, :ruby_types]
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
