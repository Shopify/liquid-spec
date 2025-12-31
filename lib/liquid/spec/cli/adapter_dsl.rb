# frozen_string_literal: true

module LiquidSpec
  class Configuration
    attr_accessor :suite, :filter, :verbose

    def initialize
      @suite = :all
      @filter = nil
      @verbose = false
    end
  end

  class << self
    attr_reader :compile_block, :render_block, :config

    def configure
      @config ||= Configuration.new
      yield @config if block_given?
      @config
    end

    def compile(&block)
      @compile_block = block
    end

    def render(&block)
      @render_block = block
    end

    def reset!
      @compile_block = nil
      @render_block = nil
      @config = nil
    end

    # Internal: compile a template using the adapter
    def do_compile(source, options = {})
      if @compile_block
        @compile_block.call(source, options)
      else
        source # Pass through if no compile block
      end
    end

    # Internal: render a template using the adapter
    def do_render(template, context)
      raise "No render block defined. Use LiquidSpec.render { |template, context| ... }" unless @render_block

      @render_block.call(template, context)
    end
  end
end
