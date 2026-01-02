# frozen_string_literal: true

require "English"
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

    # Shopify internal error handling (specific error messages, recovery behavior)
    shopify_error_handling: "Shopify-specific error handling and recovery behavior",
  }.freeze

  # An Adapter encapsulates compile/render operations for a Liquid implementation.
  # Multiple adapters can be loaded and used in the same process.
  class Adapter
    attr_reader :name, :path, :features

    def initialize(name:, path: nil, features: [:core], &block)
      @name = name
      @path = path
      @features = Array(features).map(&:to_sym)
      @features << :core unless @features.include?(:core)
      @compile_block = nil
      @render_block = nil
      @setup_block = nil
      @setup_done = false

      instance_eval(&block) if block
    end

    def setup(&block)
      @setup_block = block
    end

    def compile(&block)
      @compile_block = block
    end

    def render(&block)
      @render_block = block
    end

    def run_setup!
      return if @setup_done

      @setup_done = true
      @setup_block&.call
    end

    def do_compile(source, options = {})
      run_setup!
      raise "No compile block defined for adapter #{@name}" unless @compile_block

      @compile_block.call(source, options)
    end

    def do_render(template, assigns, options = {})
      run_setup!
      raise "No render block defined for adapter #{@name}" unless @render_block

      @render_block.call(template, assigns, options)
    end

    # Run a single spec and return { output:, error: }
    def run_spec(spec)
      compile_options = {
        line_numbers: true,
        error_mode: spec.error_mode&.to_sym,
      }.compact

      template = do_compile(spec.template, compile_options)
      template.name = spec.template_name if spec.template_name && template.respond_to?(:name=)

      render_options = {
        registers: {},
        strict_errors: false,
        exception_renderer: spec.exception_renderer,
        error_mode: spec.error_mode&.to_sym,
      }

      output = do_render(template, spec.environment || {}, render_options)
      { output: output, error: nil }
    rescue Exception => e
      { output: nil, error: "#{e.class}: #{e.message}" }
    end

    # Load an adapter from a file path
    def self.load(path)
      # Use a clean binding to capture the adapter definition
      LiquidSpec.reset!
      LiquidSpec.running_from_cli!
      Kernel.load(File.expand_path(path))

      # Convert the global DSL state to an Adapter instance
      adapter = new(
        name: File.basename(path, ".rb"),
        path: path,
        features: LiquidSpec.config&.features || [:core],
      )
      adapter.instance_variable_set(:@setup_block, LiquidSpec.setup_block)
      adapter.instance_variable_set(:@compile_block, LiquidSpec.compile_block)
      adapter.instance_variable_set(:@render_block, LiquidSpec.render_block)
      adapter
    end
  end

  class Configuration
    # CLI-controlled options
    attr_accessor :suite, :filter, :verbose, :strict_only

    # Adapter-declared features
    attr_reader :features

    def initialize
      # CLI defaults
      @suite = :all
      @filter = nil
      @verbose = false
      @strict_only = false

      # Adapter defaults
      @features = [:core]
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

    # Programmatic API for evaluating specs from Ruby code
    # Usage:
    #   require 'liquid/spec/cli/adapter_dsl'
    #   LiquidSpec.evaluate("path/to/adapter.rb", <<~YAML)
    #     hint: "Test upcase filter"
    #     complexity: 200
    #     template: "{{ 'hello' | upcase }}"
    #     expected: "HELLO"
    #   YAML
    #
    # Options:
    #   compare: true    - Compare against reference liquid-ruby
    #   verbose: true    - Show detailed output
    #
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

# When an adapter file is run directly (not through liquid-spec CLI),
# show a helpful message. Skip this when running in Ruby::Box since
# the adapter is being loaded programmatically.
unless defined?(Ruby::Box) && Ruby::Box.current && !Ruby::Box.current.main?
  at_exit do
    unless LiquidSpec.running_from_cli? || $ERROR_INFO
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
end
