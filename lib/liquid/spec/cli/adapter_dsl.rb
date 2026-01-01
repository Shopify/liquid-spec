# frozen_string_literal: true

module LiquidSpec
  class Configuration
    attr_accessor :suite, :filter, :verbose, :strict_only, :features

    # Default suite when not specified via CLI (defaults to :liquid_ruby)
    DEFAULT_SUITE = :liquid_ruby

    # Default features that most Liquid implementations support
    DEFAULT_FEATURES = [:core].freeze

    def initialize
      @suite = DEFAULT_SUITE
      @filter = nil
      @verbose = false
      @strict_only = false
      @features = DEFAULT_FEATURES.dup
    end

    # Check if a feature is supported
    def feature?(name)
      @features.include?(name.to_sym)
    end

    # Add features
    def add_features(*names)
      names.each { |n| @features << n.to_sym unless @features.include?(n.to_sym) }
    end
  end

  # Context passed to render block - provides clean, ready-to-use data
  class Context
    attr_reader :environment,
      :file_system,
      :exception_renderer,
      :template_factory,
      :error_mode,
      :render_errors,
      :context_klass

    def initialize(spec_context)
      # Deep copy environment to avoid mutation
      env = spec_context[:environment] || {}
      # Use deep_dup if available (ActiveSupport), otherwise Marshal
      # Marshal fails with TestDrops objects due to module lookup issues
      @environment = env.respond_to?(:deep_dup) ? env.deep_dup : Marshal.load(Marshal.dump(env))

      @file_system = spec_context[:file_system]
      @exception_renderer = spec_context[:exception_renderer]
      @template_factory = spec_context[:template_factory]
      @error_mode = spec_context[:error_mode]
      @render_errors = spec_context[:render_errors]
      @context_klass = spec_context[:context_klass]
    end

    # Build registers hash with file_system and template_factory
    def registers
      {
        file_system: @file_system,
        template_factory: @template_factory,
      }.compact
    end

    # Should errors be rethrown or rendered inline?
    def rethrow_errors?
      !@render_errors
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
    def compile(&block)
      @compile_block = block
    end

    # Define how to render a compiled template
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
    def do_render(template, context)
      run_setup!
      raise "No render block defined. Use LiquidSpec.render { |template, ctx| ... }" unless @render_block

      ctx = Context.new(context)
      @render_block.call(template, ctx)
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
