#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter (pure Ruby, no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.rubyopt "--yjit"

LiquidSpec.setup do |ctx|
  require "liquid"
  require "active_support/all"

  # Disable liquid-c if present
  if defined?(Liquid::C) && Liquid::C.respond_to?(:enabled=)
    Liquid::C.enabled = false
  end
end

LiquidSpec.configure do |config|
  config.error_modes = [:strict2, :strict]
  config.render_error_modes = [:raise, :inline]
  config.missing_features = [:drop_class_output, :shopify_tags, :shopify_objects, :shopify_filters, :shopify_includes, :shopify_blank, :shopify_error_handling, :shopify_error_format, :shopify_string_access, :shopify_resource_limits, :strict2_blank_body_errors]
end

LiquidSpec.compile do |ctx, source, parse_options|
  ctx[:template] = Liquid::Template.parse(source, **parse_options)
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
