# frozen_string_literal: true

module LiquidSpec
  class Configuration
    attr_accessor :suite, :filter, :verbose, :error_mode

    def initialize
      @suite = :all
      @filter = nil
      @verbose = false
      @error_mode = :lax
    end
  end

  class ContextBuilder
    attr_reader :assigns, :registers, :environment, :exception_renderer, :template_factory

    def initialize(spec_context)
      @assigns = spec_context[:assigns] || {}
      @registers = spec_context[:registers] || {}
      @environment = spec_context[:environment] || {}
      @exception_renderer = spec_context[:exception_renderer]
      @template_factory = spec_context[:template_factory]
    end

    # All variables merged (environment + assigns)
    def variables
      environment.merge(assigns)
    end

    def file_system
      registers[:file_system]
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
    #
    # @example
    #   LiquidSpec.compile do |source, options|
    #     Liquid::Template.parse(source, **options)
    #   end
    #
    def compile(&block)
      @compile_block = block
    end

    # Define how to render a compiled template
    #
    # @example Simple - just pass variables
    #   LiquidSpec.render do |template, ctx|
    #     template.render(ctx.variables)
    #   end
    #
    # @example Full - use all context info
    #   LiquidSpec.render do |template, ctx|
    #     liquid_ctx = Liquid::Context.new(
    #       [ctx.environment, ctx.assigns],
    #       {},
    #       ctx.registers
    #     )
    #     template.render(liquid_ctx)
    #   end
    #
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
      if @compile_block
        @compile_block.call(source, options)
      else
        source # Pass through if no compile block
      end
    end

    # Internal: render a template using the adapter
    def do_render(template, context)
      run_setup!
      raise "No render block defined. Use LiquidSpec.render { |template, ctx| ... }" unless @render_block

      ctx = ContextBuilder.new(context)
      @render_block.call(template, ctx)
    end

    # Mark that we're running through the CLI
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
