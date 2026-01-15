# frozen_string_literal: true

require "timeout"

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
#   LiquidSpec.compile do |ctx, source, parse_options|
#     ctx[:template] = MyLiquid::Template.parse(source, **parse_options)
#   end
#
#   LiquidSpec.render do |ctx, assigns, render_options|
#     ctx[:template].render(assigns, **render_options)
#   end

module LiquidSpec
  DEFAULT_ADAPTER_TIMEOUT = 3

  # Raised when an adapter compile/render call exceeds the timeout budget
  class AdapterTimeoutError < StandardError
    attr_reader :phase, :spec_name, :template_name, :source_file, :timeout_seconds

    def initialize(phase:, timeout_seconds:, spec_name: nil, template_name: nil, source_file: nil)
      @phase = phase
      @spec_name = spec_name
      @template_name = template_name
      @source_file = source_file
      @timeout_seconds = timeout_seconds

      message = ["Adapter #{phase} timed out after #{format_timeout(timeout_seconds)}"]
      details = []
      details << "spec: #{spec_name}" if spec_name
      details << "template: #{template_name}" if template_name
      details << source_file if source_file
      message << "(#{details.join(", ")})" unless details.empty?
      super(message.join(" "))
    end

    private

    def format_timeout(value)
      value.to_f == value.to_i ? "#{value.to_i}s" : "#{value}s"
    end
  end
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
    attr_reader :features, :known_failures

    def initialize
      @suite = :all
      @filter = nil
      @verbose = false
      @strict_only = false
      @features = [:core]
      @known_failures = []
      expand_features!
    end

    def features=(list)
      @features = Array(list).map(&:to_sym)
      expand_features!
    end

    def known_failures=(list)
      @known_failures = Array(list).map(&:to_s)
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
    attr_reader :adapter_timeout_seconds

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
    # Block receives: ctx, source, parse_options
    # Should store the template in ctx[:template]
    def compile(&block)
      @compile_block = block
    end

    # Define how to render a compiled template
    # Block receives: ctx, assigns, render_options
    # Template should be retrieved from ctx[:template] (set during compile)
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
      env_timeout = ENV["LIQUID_SPEC_ADAPTER_TIMEOUT"]
      @adapter_timeout_seconds = DEFAULT_ADAPTER_TIMEOUT
      if env_timeout && !env_timeout.strip.empty?
        begin
          @adapter_timeout_seconds = parse_timeout_value(env_timeout)
        rescue ArgumentError => e
          warn "[liquid-spec] Ignoring invalid LIQUID_SPEC_ADAPTER_TIMEOUT '#{env_timeout}': #{e.message}"
          @adapter_timeout_seconds = DEFAULT_ADAPTER_TIMEOUT
        end
      end
    end

    def run_setup!
      return if @setup_done

      @setup_done = true
      @ctx ||= {}

      # Autoload Liquid so adapters can require it without full path
      Object.autoload(:Liquid, "liquid") unless defined?(::Liquid)

      @setup_block&.call(@ctx)
    end

    def do_compile(source, options = {}, context = nil)
      run_setup!
      raise "No compile block defined. Use LiquidSpec.compile { |ctx, source, options| ... }" unless @compile_block

      invoke_adapter_phase(:compile, context) { @compile_block.call(@ctx, source, options) }
    end

    def do_render(assigns, render_options = {}, context = nil)
      run_setup!
      raise "No render block defined. Use LiquidSpec.render { |ctx, assigns, render_options| ... }" unless @render_block

      invoke_adapter_phase(:render, context) { @render_block.call(@ctx, assigns, render_options) }
    end

    def adapter_timeout_seconds=(value)
      raise ArgumentError, "Adapter timeout must be provided" if value.nil?

      @adapter_timeout_seconds = parse_timeout_value(value)
    end

    def adapter_context(spec = nil, overrides = {})
      context = {}

      if spec
        context[:spec_name] = spec.name if spec.respond_to?(:name) && spec.name
        if spec.respond_to?(:template_name) && spec.template_name
          context[:template_name] = spec.template_name
        end
        if spec.respond_to?(:source_file) && spec.source_file
          location = spec.source_file
          if spec.respond_to?(:line_number) && spec.line_number
            location = "#{location}:#{spec.line_number}"
          end
          context[:source_file] = location
        end
      end

      overrides&.each do |key, value|
        if value.nil? && key.to_sym != :adapter_timeout
          next
        end
        context[key.to_sym] = value
      end

      context
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
      eval_options[:adapter_timeout] = options[:adapter_timeout] if options.key?(:adapter_timeout)

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

    private

    def invoke_adapter_phase(phase, context)
      timeout = extract_timeout(context)
      return yield unless timeout && timeout.positive?

      spec_name = context && (context[:spec_name] || context["spec_name"])
      template_name = context && (context[:template_name] || context["template_name"])
      source_file = context && (context[:source_file] || context["source_file"])

      Timeout.timeout(timeout) { yield }
    rescue Timeout::Error
      raise AdapterTimeoutError.new(
        phase: phase,
        timeout_seconds: timeout,
        spec_name: spec_name,
        template_name: template_name,
        source_file: source_file,
      )
    end

    def extract_timeout(context)
      return context[:adapter_timeout] if context&.key?(:adapter_timeout)
      return context["adapter_timeout"] if context&.key?("adapter_timeout")

      @adapter_timeout_seconds
    end

    def parse_timeout_value(value)
      str = value.to_s.strip
      raise ArgumentError, "Adapter timeout must be a positive number of seconds" if str.empty?

      seconds = Float(str)
      raise ArgumentError, "Adapter timeout must be greater than 0 seconds" if seconds <= 0

      seconds
    rescue ArgumentError
      raise ArgumentError, "Adapter timeout must be a positive number of seconds"
    end
  end
end
