#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter (pure Ruby, no liquid-c)
#
# Run: liquid-spec examples/liquid_ruby.rb
#

require "liquid/spec/cli/adapter_dsl"

LiquidSpec.rubyopt "--zjit"

LiquidSpec.setup do |ctx|
  require "liquid"
  require "active_support/all"

  # Disable liquid-c if present
  if defined?(Liquid::C) && Liquid::C.respond_to?(:enabled=)
    Liquid::C.enabled = false
  end
end

LiquidSpec.configure do |config|
  config.missing_features = [:drop_class_output, :shopify_filters, :shopify_includes, :shopify_blank, :shopify_error_handling, :shopify_error_format, :shopify_string_access, :lax_parsing]
end

LiquidSpec.compile do |ctx, source, parse_options|
  # Use spec's error_mode if provided, default to :strict
  parse_options[:error_mode] ||= :strict
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
