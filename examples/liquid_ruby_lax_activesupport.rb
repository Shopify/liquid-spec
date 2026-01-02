#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter with ActiveSupport (lax mode, no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby_lax_activesupport.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "active_support/all"
  require "liquid"

  # Disable liquid-c if present
  if defined?(Liquid::C)
    Liquid::C.enabled = false
  end
end

LiquidSpec.configure do |config|
  config.features = [:core, :lax_parsing, :activesupport]
end

LiquidSpec.compile do |source, options|
  Liquid::Template.parse(source, **options)
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
