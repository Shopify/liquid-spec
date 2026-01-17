# frozen_string_literal: true

# Liquid Spec Adapter
#
# This file defines how your Liquid implementation compiles and renders templates.
# Implement the methods below to test your implementation against the spec.
#
# Run with: liquid-spec run liquid_adapter.rb

LiquidSpec.setup do |ctx|
  # ctx is a hash for storing adapter state (environment, file_system, etc.)
  # Example: ctx[:environment] = MyLiquid::Environment.new
end

LiquidSpec.configure do |config|
  # Which spec suites to run: :all, :liquid_ruby, :dawn
  config.suite = :liquid_ruby

  # Optional: filter specs by name pattern
  # config.filter = /assign/
end

# Called to compile a template string into your implementation's template object.
#
# @param ctx [Hash] Adapter context (from setup block)
# @param source [String] The Liquid template source code
# @param options [Hash] Parse options (e.g., :error_mode, :line_numbers)
# @return [Object] Your compiled template object (passed to render)
#
LiquidSpec.compile do |ctx, source, options|
  # Example for Shopify/liquid:
  #   Liquid::Template.parse(source, options)
  #
  # Example for a custom implementation:
  #   MyLiquid::Template.new(source)
  #
  raise NotImplementedError, "Implement LiquidSpec.compile to parse templates"
end

# Called to render a compiled template with the given context.
#
# @param ctx [Hash] Adapter context (from setup block)
# @param template [Object] The compiled template (from compile block)
# @param assigns [Hash] Variables available as {{ var }}
# @param options [Hash] Render options (:registers, :strict_errors, :error_mode)
# @return [String] The rendered output
#
LiquidSpec.render do |ctx, template, assigns, options|
  # Example for Shopify/liquid:
  #   context = Liquid::Context.build(
  #     static_environments: assigns,
  #     registers: Liquid::Registers.new(options[:registers] || {})
  #   )
  #   template.render(context)
  #
  # Example for a custom implementation:
  #   template.render(assigns)
  #
  raise NotImplementedError, "Implement LiquidSpec.render to render templates"
end
