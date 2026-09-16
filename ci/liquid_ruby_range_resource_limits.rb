#!/usr/bin/env ruby
# frozen_string_literal: true

# Candidate reference for range resource-limit regressions. This loads Liquid
# from the CI checkout named by LIQUID_RANGE_REFERENCE_PATH before the standard
# adapter is defined, then opts into only the staged range capability.
# Run: LIQUID_RANGE_REFERENCE_PATH=/path/to/liquid liquid-spec run ci/liquid_ruby_range_resource_limits.rb

range_reference_path = ENV.fetch("LIQUID_RANGE_REFERENCE_PATH")
liquid_lib = File.join(File.expand_path(range_reference_path), "lib")
raise "LIQUID_RANGE_REFERENCE_PATH must contain lib/liquid.rb" unless File.file?(File.join(liquid_lib, "liquid.rb"))

$LOAD_PATH.unshift(liquid_lib)
require "liquid"
require_relative "../examples/liquid_ruby"

LiquidSpec.configure do |config|
  # This adapter is invoked only by the filtered staged CI job. It has the same
  # capabilities as the ordinary Ruby adapter, plus range resource limits.
  config.missing_features = [:self_environment_shadowing, :drop_class_output, :shopify_tags, :shopify_objects, :shopify_filters, :shopify_includes, :shopify_blank, :shopify_error_handling, :shopify_error_format, :shopify_string_access, :strict2_blank_body_errors]
end
