# frozen_string_literal: true

# LiquidSpec DSL for defining adapters
#
# Usage in adapter files:
#   LiquidSpec.setup do |ctx|
#     require "my_liquid"
#     # ctx is a hash you can store adapter state in
#     ctx[:environment] = MyLiquid::Environment.new
#   end
#
#   LiquidSpec.configure do |config|
#     config.suite = :liquid_ruby
#     config.features = [:core, :lax_parsing]
#   end
#
#   LiquidSpec.compile do |ctx, source, options|
#     MyLiquid::Template.parse(source, environment: ctx[:environment], **options)
#   end
#
#   LiquidSpec.render do |ctx, template, assigns, options|
#     template.render(assigns, **options)
#   end

module LiquidSpec
  # Standard features that can be declared by adapters
  FEATURES = {
    core: "Full Liquid implementation with runtime drop support",
    runtime_drops: "Supports bidirectional communication for drop callbacks",
    lax_parsing: "Supports error_mode: :lax for lenient parsing",
    shopify_tags: "Shopify-specific tags (schema, style, section, etc.)",
    shopify_objects: "Shopify-specific objects (section, block, content_for_header)",
    shopify_filters: "Shopify-specific filters (asset_url, image_url, etc.)",
    shopify_error_handling: "Shopify-specific error handling and recovery behavior",
  }.freeze

  # Feature expansions - declaring a feature automatically includes these
  # :core is the "full implementation" feature that includes runtime drop support
  # JSON-RPC adapters that can't support runtime drops should not declare :core
  FEATURE_EXPANSIONS = {
    core: [:runtime_drops],
  }.freeze

  # Default features when no config is set (matches Configuration defaults after expansion)
  DEFAULT_FEATURES = [:core, :runtime_drops].freeze

  class Configuration
    attr_accessor :suite, :filter, :verbose, :strict_only
    attr_reader :features

    def initialize
      @suite = :all
      @filter = nil
      @verbose = false
      @strict_only = false
      @features = [:core]
      expand_features!
    end

    def features=(list)
      @features = Array(list).map(&:to_sym)
      expand_features!
    end

    def feature?(name)
      @features.include?(name.to_sym)
    end

    private

    def expand_features!
      FEATURE_EXPANSIONS.each do |feature, includes|
        if @features.include?(feature)
          @features |= includes
        end
      end
    end
  end

  # Exception raised when an adapter should be skipped
  class SkipAdapter < StandardError; end

  class << self
    attr_reader :compile_block, :render_block, :config, :setup_block, :ctx
    attr_accessor :cli_options

    # Skip this adapter with a reason
    def skip!(reason)
      raise SkipAdapter, reason
    end

    def configure
      @config ||= Configuration.new
      yield @config if block_given?
      @config
    end

    def features
      @config&.instance_variable_get(:@features) || DEFAULT_FEATURES
    end

    # Called once before running specs
    # Block receives ctx hash for storing adapter state
    def setup(&block)
      @setup_block = block
    end

    # Define how to compile/parse a template
    # Block receives: ctx, source, options
    def compile(&block)
      @compile_block = block
    end

    # Define how to render a compiled template
    # Block receives: ctx, template, assigns, options
    def render(&block)
      @render_block = block
    end

    def reset!
      @compile_block = nil
      @render_block = nil
      @setup_block = nil
      @config = nil
      @ctx = {}
      @cli_options = {}
      @running_from_cli = false
      @setup_done = false
    end

    def run_setup!
      return if @setup_done

      @setup_done = true
      @ctx ||= {}
      @setup_block&.call(@ctx)
    end

    def do_compile(source, options = {})
      run_setup!
      raise "No compile block defined. Use LiquidSpec.compile { |ctx, source, options| ... }" unless @compile_block

      @compile_block.call(@ctx, source, options)
    end

    def do_render(template, assigns, options = {})
      run_setup!
      raise "No render block defined. Use LiquidSpec.render { |ctx, template, assigns, options| ... }" unless @render_block

      @render_block.call(@ctx, template, assigns, options)
    end

    def running_from_cli!
      @running_from_cli = true
    end

    def running_from_cli?
      @running_from_cli
    end

    # Programmatic API for evaluating specs from Ruby code
    def evaluate(adapter_path, yaml_or_hash, options = {})
      require_relative "eval"

      reset!
      @running_from_cli = true
      load(File.expand_path(adapter_path))

      eval_options = {
        verbose: options[:verbose],
        compare: options[:compare],
        assigns: {},
      }

      if yaml_or_hash.is_a?(Hash)
        eval_options[:liquid] = yaml_or_hash[:template] || yaml_or_hash["template"]
        eval_options[:expected] = yaml_or_hash[:expected] || yaml_or_hash["expected"]
        eval_options[:assigns] = yaml_or_hash[:environment] || yaml_or_hash["environment"] ||
          yaml_or_hash[:assigns] || yaml_or_hash["assigns"] || {}
        eval_options[:spec_data] = yaml_or_hash.transform_keys(&:to_s)
      else
        eval_options[:stdin_yaml] = yaml_or_hash.to_s
      end

      Liquid::Spec::CLI::Eval.run_eval(eval_options, adapter_path)
    end
  end
end
