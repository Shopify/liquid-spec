# frozen_string_literal: true

require_relative "adapter_dsl"

module Liquid
  module Spec
    module CLI
      module Features
        FEATURE_DOCS = {
          core: {
            description: "Full Liquid implementation with runtime drop support",
            recommendation: :required,
            note: "Essential for any Liquid implementation. Includes runtime_drops and inline_errors.",
          },
          runtime_drops: {
            description: "Supports bidirectional communication for drop callbacks",
            recommendation: :required,
            note: "Needed for dynamic object property access. Included with :core.",
          },
          inline_errors: {
            description: "Supports render_errors mode (errors rendered inline instead of raised)",
            recommendation: :required,
            note: "Liquid renders errors inline by default. Included with :core.",
          },
          ruby_types: {
            description: "Supports Ruby-specific types (symbols in hash keys/output)",
            recommendation: :unnecessary,
            note: "Ruby implementation detail. Non-Ruby implementations can skip these tests.",
          },
          lax_parsing: {
            description: "Supports error_mode: :lax for lenient parsing",
            recommendation: :unnecessary,
            note: "Strict parsing should be the default. Lax mode is for legacy compatibility.",
          },
          strict_parsing: {
            description: "Supports error_mode: :strict (recommended default)",
            recommendation: :required,
            note: "New implementations should default to strict mode.",
          },
          shopify_tags: {
            description: "Shopify-specific tags (schema, style, section, etc.)",
            recommendation: :optional,
            note: "Only needed for Shopify theme compatibility.",
          },
          shopify_objects: {
            description: "Shopify-specific objects (section, block, content_for_header)",
            recommendation: :optional,
            note: "Only needed for Shopify theme compatibility.",
          },
          shopify_filters: {
            description: "Shopify-specific filters (asset_url, image_url, etc.)",
            recommendation: :optional,
            note: "Only needed for Shopify theme compatibility.",
          },
          shopify_error_handling: {
            description: "Shopify-specific error handling and recovery behavior",
            recommendation: :optional,
            note: "Only needed for Shopify production compatibility.",
          },
          shopify_blank: {
            description: "Shopify-specific blank keyword with Rails-like semantics",
            recommendation: :optional,
            note: "Shopify's blank matches false, [], {}, whitespace. Standard blank calls blank?.",
          },
          shopify_string_access: {
            description: "Shopify-specific string.first/last character access",
            recommendation: :optional,
            note: "In Shopify, first/last work on strings. Standard liquid-ruby doesn't support this.",
          },
          shopify_error_format: {
            description: "Shopify-specific error message formatting",
            recommendation: :optional,
            note: "Only needed for Shopify production compatibility.",
          },
          shopify_includes: {
            description: "Shopify-specific include/render behavior",
            recommendation: :optional,
            note: "Only needed for Shopify theme compatibility.",
          },
          ruby_drops: {
            description: "Tests requiring Ruby drop objects with specific behavior",
            recommendation: :unnecessary,
            note: "Ruby implementation detail. Tests internal drop mechanics.",
          },
          drop_class_output: {
            description: "Tests expecting drop class name in output (Liquid::Drop)",
            recommendation: :unnecessary,
            note: "Ruby-specific. JSON-RPC renders drops as class name string.",
          },
          template_factory: {
            description: "Tests using custom template factories for partial lookup",
            recommendation: :unnecessary,
            note: "Ruby-specific. JSON-RPC doesn't support custom template factories.",
          },
          binary_data: {
            description: "Tests with binary/non-UTF8 data",
            recommendation: :unnecessary,
            note: "Binary data can't be transmitted in JSON without base64 encoding.",
          },
          activesupport: {
            description: "Tests requiring ActiveSupport (Rails) extensions",
            recommendation: :unnecessary,
            note: "Only needed if targeting Rails environments. SafeBuffer, etc.",
          },
        }.freeze

        RECOMMENDATION_LABELS = {
          required: "\e[32mREQUIRED\e[0m",
          unnecessary: "\e[33mUNNECESSARY\e[0m",
          optional: "\e[36mOPTIONAL\e[0m",
        }.freeze

        def self.run(args)
          counts = count_specs_by_feature
          total_specs = count_total_specs

          puts "liquid-spec Features"
          puts "=" * 60
          puts
          puts "Features control which specs are run. Declare them in your adapter:"
          puts
          puts "  LiquidSpec.configure do |config|"
          puts "    config.features = [:core, :strict_parsing]"
          puts "  end"
          puts
          puts "-" * 60
          puts

          FEATURE_DOCS.each do |feature, doc|
            count = counts[feature] || 0
            label = RECOMMENDATION_LABELS[doc[:recommendation]]

            puts "#{feature}"
            puts "  #{label}  #{count} specs"
            puts "  #{doc[:description]}"
            puts "  → #{doc[:note]}"
            puts
          end

          puts "-" * 60
          puts
          puts "Summary:"
          puts "  Total specs: #{total_specs}"
          puts "  Specs requiring special features:"
          counts.each do |feature, count|
            next if count == 0 || feature == :core
            puts "    #{feature}: #{count}"
          end
          puts
          puts "Recommended starter config:"
          puts "  config.features = [:core, :strict_parsing]"
          puts
        end

        def self.count_specs_by_feature
          counts = Hash.new(0)

          Dir.glob(File.join(spec_root, "**/*.yml")).each do |file|
            begin
              content = File.read(file)
              data = YAML.safe_load(content, permitted_classes: [Symbol, Range], aliases: true)
              next unless data

              specs = data.is_a?(Array) ? data : (data["specs"] || [])
              metadata = data.is_a?(Hash) ? data["_metadata"] : nil

              specs.each do |spec|
                next unless spec.is_a?(Hash)

                # Get required features from spec or metadata
                features = spec["required_features"] ||
                           (metadata && metadata["required_features"]) ||
                           []

                features = [features] unless features.is_a?(Array)
                features.each do |f|
                  counts[f.to_sym] += 1
                end
              end
            rescue => e
              # Skip files with parse errors
            end
          end

          counts
        end

        def self.count_total_specs
          total = 0

          Dir.glob(File.join(spec_root, "**/*.yml")).each do |file|
            begin
              content = File.read(file)
              data = YAML.safe_load(content, permitted_classes: [Symbol, Range], aliases: true)
              next unless data

              specs = data.is_a?(Array) ? data : (data["specs"] || [])
              total += specs.count { |s| s.is_a?(Hash) && s["name"] }
            rescue
            end
          end

          total
        end

        def self.spec_root
          File.expand_path("../../../../specs", __dir__)
        end
      end
    end
  end
end
