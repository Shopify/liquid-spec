#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter with ActiveSupport (no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby_activesupport.rb
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
  config.features = [:core, :activesupport, :strict_parsing]
end

LiquidSpec.compile do |ctx, source, options|
  # Force strict mode regardless of spec (override comes after splat)
  Liquid::Template.parse(source, **options, error_mode: :strict)
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
