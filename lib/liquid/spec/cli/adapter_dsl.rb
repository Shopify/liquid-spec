# frozen_string_literal: true

module LiquidSpec
  # Standard features that can be declared by adapters
  # Suites require specific features to run
  FEATURES = {
    # Core Liquid parsing and rendering (always enabled by default)
    core: "Basic Liquid template parsing and rendering",

    # Lax error mode - tolerates invalid syntax (deprecated backwards-compat mode)
    lax_parsing: "Supports error_mode: :lax for lenient parsing",

    # Shopify-specific extensions
    shopify_tags: "Shopify-specific tags (schema, style, section, etc.)",
    shopify_objects: "Shopify-specific objects (section, block, content_for_header)",
    shopify_filters: "Shopify-specific filters (asset_url, image_url, etc.)",
  }.freeze

  class Configuration
    attr_accessor :suite, :filter, :verbose, :strict_only
    attr_reader :features

    # Default suite - :all runs all suites the adapter supports
    DEFAULT_SUITE = :all

    def initialize
      @suite = DEFAULT_SUITE
      @filter = nil
      @verbose = false
      @strict_only = false
      @features = [:core] # Core is always enabled by default
    end

    # Set the features this adapter implements
    def features=(list)
      @features = Array(list).map(&:to_sym)
      # Core is always included
      @features << :core unless @features.include?(:core)
    end

    # Check if a feature is supported
    def feature?(name)
      @features.include?(name.to_sym)
    end
  end

  class << self
    attr_reader :compile_block, :render_block, :config, :setup_block

    def configure
      @config ||= Configuration.new
      yield @config if block_given?
      @config
    end

    # Called once before running specs - use for requiring gems, setup, etc.
    def setup(&block)
      @setup_block = block
    end

    # Define how to compile/parse a template
    # Block receives: |source, options|
    def compile(&block)
      @compile_block = block
    end

    # Define how to render a compiled template
    # Block receives: |template, assigns, options|
    def render(&block)
      @render_block = block
    end

    def reset!
      @compile_block = nil
      @render_block = nil
      @setup_block = nil
      @config = nil
      @running_from_cli = false
      @setup_done = false
    end

    # Internal: run setup block once
    def run_setup!
      return if @setup_done

      @setup_done = true
      @setup_block&.call
    end

    # Internal: compile a template using the adapter
    def do_compile(source, options = {})
      run_setup!
      raise "No compile block defined. Use LiquidSpec.compile { |source, options| ... }" unless @compile_block

      @compile_block.call(source, options)
    end

    # Internal: render a template using the adapter
    def do_render(template, assigns, options = {})
      run_setup!
      raise "No render block defined. Use LiquidSpec.render { |template, assigns, options| ... }" unless @render_block

      @render_block.call(template, assigns, options)
    end

    def running_from_cli!
      @running_from_cli = true
    end

    def running_from_cli?
      @running_from_cli
    end
  end
end

# When an adapter file is run directly (not through liquid-spec CLI),
# show a helpful message
at_exit do
  unless LiquidSpec.running_from_cli? || $!
    if LiquidSpec.compile_block || LiquidSpec.render_block
      adapter_file = $PROGRAM_NAME
      $stderr.puts <<~MSG

        This is a liquid-spec adapter. Run it with:

          liquid-spec #{adapter_file}

        Options:
          liquid-spec #{adapter_file} -n PATTERN   # filter by test name
          liquid-spec #{adapter_file} -v           # verbose output
          liquid-spec #{adapter_file} -l           # list available specs

        See all options:
          liquid-spec --help

      MSG
      exit 1
    end
  end
end
