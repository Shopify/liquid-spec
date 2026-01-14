# frozen_string_literal: true

require "stringio"
require_relative "time_freezer"

module Liquid
  module Spec
    # Runs specs against a loaded adapter
    class AdapterRunner
      TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze
      TEST_TZ = "America/New_York"

      attr_reader :name, :features, :ctx

      def initialize(name: nil)
        @name = name
        @features = Set.new([:core])
        @setup_block = nil
        @compile_block = nil
        @render_block = nil
        @setup_done = false
        @ctx = {}
      end

      # Load adapter DSL from a file
      def load_dsl(path)
        path = "#{path}.rb" unless path.end_with?(".rb")
        path = File.expand_path(path)

        raise "Adapter file not found: #{path}" unless File.exist?(path)

        @name ||= File.basename(path, ".rb")

        # Load the adapter DSL
        require_relative "cli/adapter_dsl"
        ::LiquidSpec.reset!
        ::LiquidSpec.running_from_cli!
        silence_output { Kernel.load(path) }

        # Extract the DSL values from the LiquidSpec module
        @setup_block = ::LiquidSpec.instance_variable_get(:@setup_block)
        @compile_block = ::LiquidSpec.instance_variable_get(:@compile_block)
        @render_block = ::LiquidSpec.instance_variable_get(:@render_block)

        config = ::LiquidSpec.instance_variable_get(:@config)
        if config&.respond_to?(:features)
          set_features(config.features)
        end

        # Validate block signatures
        validate_blocks!

        self
      end

      # Validate that compile and render blocks have correct signatures
      def validate_blocks!
        errors = []

        if @compile_block
          arity = @compile_block.arity
          params = @compile_block.parameters
          expected_params = [[:opt, :ctx], [:opt, :source], [:opt, :parse_options]]

          unless arity == 3 || arity == -1
            errors << "compile block has wrong arity (#{arity}, expected 3)"
          end

          # Check first param is ctx-like
          if params[0] && ![:ctx, :context, :c].include?(params[0][1])
            errors << "compile block first param should be ctx, got #{params[0][1]}"
          end
        else
          errors << "compile block is not defined"
        end

        if @render_block
          arity = @render_block.arity
          params = @render_block.parameters

          unless arity == 3 || arity == -1
            errors << "render block has wrong arity (#{arity}, expected 3)"
          end

          # Check first param is ctx-like
          if params[0] && ![:ctx, :context, :c].include?(params[0][1])
            errors << "render block first param should be ctx, got #{params[0][1]}"
          end

          # Warn if second param looks like 'template' (old API)
          if params[1] && params[1][1] == :template
            errors << "render block second param is 'template' - this is the old API. " \
                      "New API: render do |ctx, assigns, render_options| with template from ctx[:template]"
          end
        else
          errors << "render block is not defined"
        end

        if errors.any?
          error_msg = "Adapter '#{@name}' has invalid block signatures:\n  " + errors.join("\n  ")
          error_msg += "\n\nExpected signatures:\n"
          error_msg += "  LiquidSpec.compile do |ctx, source, parse_options|\n"
          error_msg += "    ctx[:template] = ...\n"
          error_msg += "  end\n"
          error_msg += "\n"
          error_msg += "  LiquidSpec.render do |ctx, assigns, render_options|\n"
          error_msg += "    ctx[:template].render(...)\n"
          error_msg += "  end"
          raise ArgumentError, error_msg
        end
      end

      # Introspection: get info about adapter blocks
      def block_info
        {
          compile: block_signature_info(@compile_block, "compile"),
          render: block_signature_info(@render_block, "render"),
        }
      end

      # Run setup if not already done
      def ensure_setup!
        return if @setup_done

        @setup_block&.call(@ctx)
        @setup_done = true

        # Load drop support after setup (liquid gem must be loaded first)
        require_relative "deps/liquid_ruby"
        require_relative "yaml_initializer"
      end

      # Set the setup block
      def on_setup(&block)
        @setup_block = block
      end

      # Set the compile block
      def on_compile(&block)
        @compile_block = block
      end

      # Set the render block
      def on_render(&block)
        @render_block = block
      end

      # Set features
      def set_features(features)
        @features = Set.new(features.map(&:to_sym))
        @features << :core unless @features.include?(:core)
      end

      # Check if adapter can run a spec
      def can_run?(spec)
        spec.runnable_with?(@features)
      end

      # Run a batch of specs
      # Yields each result as it completes (for progress reporting)
      # Returns a RunResult with aggregate stats
      def run(specs)
        ensure_setup!

        result = RunResult.new(adapter: self, specs: specs)

        # Set timezone and freeze time for consistent results
        original_tz = ENV["TZ"]
        ENV["TZ"] = TEST_TZ

        begin
          TimeFreezer.freeze(TEST_TIME) do
            specs.each do |spec|
              spec_result = run_single(spec)
              result.add(spec_result)
              yield spec_result if block_given?
            end
          end
        ensure
          ENV["TZ"] = original_tz
        end

        result
      end

      # Run a single spec
      def run_single(spec)
        unless can_run?(spec)
          return SpecResult.new(
            spec: spec,
            status: :skipped,
            reason: "Missing features: #{(spec.required_features - @features.to_a).join(", ")}",
          )
        end

        begin
          # Instantiate environment (drops) for this spec
          environment = spec.instantiate_environment
          filesystem = spec.instantiate_filesystem
          template_factory = spec.instantiate_template_factory

          # Make current spec available in ctx
          @ctx[:spec] = spec

          # Compile
          compile_options = { line_numbers: true }
          compile_options[:error_mode] = spec.error_mode if spec.error_mode
          compile_options[:file_system] = filesystem if filesystem
          compile_options[:template_name] = spec.template_name if spec.template_name

          @compile_block.call(@ctx, spec.template, compile_options)

          # Render
          registers = {}
          registers[:file_system] = filesystem if filesystem
          registers[:template_factory] = template_factory if template_factory

          render_options = {
            registers: registers,
            strict_errors: false,
          }
          render_options[:error_mode] = spec.error_mode if spec.error_mode

          output = @render_block.call(@ctx, environment, render_options)

          # Compare
          check_result(spec, output: output.to_s)
        rescue ::StandardError => e
          # Check if this was an expected error
          # NOTE: Must use ::StandardError to avoid resolving to Liquid::StandardError
          check_result(spec, error: "#{e.class}: #{e.message}")
        end
      end

      private

      def block_signature_info(block, name)
        return { defined: false } unless block

        params = block.parameters
        {
          defined: true,
          arity: block.arity,
          parameters: params,
          param_names: params.map { |_, n| n },
          signature: "#{name} do |#{params.map { |_, n| n }.join(", ")}|",
        }
      end

      def silence_output
        original_stdout = $stdout
        original_stderr = $stderr
        $stdout = StringIO.new
        $stderr = StringIO.new
        yield
      ensure
        $stdout = original_stdout
        $stderr = original_stderr
      end

      def check_result(spec, output: nil, error: nil)
        # If we got an error, check if it was expected
        if error
          if spec.errors.any? && matches_error_patterns?(spec, error)
            return SpecResult.new(spec: spec, status: :pass, output: error)
          elsif spec.errors.any?
            return SpecResult.new(
              spec: spec,
              status: :fail,
              output: error,
              expected: "error matching #{spec.errors.inspect}",
            )
          else
            return SpecResult.new(
              spec: spec,
              status: :error,
              output: error,
              expected: spec.expected,
            )
          end
        end

        # No error - check expected output
        if spec.expected
          if output == spec.expected
            SpecResult.new(spec: spec, status: :pass, output: output)
          else
            SpecResult.new(
              spec: spec,
              status: :fail,
              output: output,
              expected: spec.expected,
            )
          end
        elsif spec.errors.key?("output") || spec.errors.key?(:output)
          patterns = spec.errors["output"] || spec.errors[:output]
          if matches_patterns?(output, patterns)
            SpecResult.new(spec: spec, status: :pass, output: output)
          else
            SpecResult.new(
              spec: spec,
              status: :fail,
              output: output,
              expected: "output matching #{patterns.inspect}",
            )
          end
        else
          # No expected value - pass by default
          SpecResult.new(spec: spec, status: :pass, output: output)
        end
      end

      def matches_error_patterns?(spec, error)
        spec.errors.any? do |type, patterns|
          type_s = type.to_s
          next false unless ["parse_error", "render_error", "output"].include?(type_s)

          matches_patterns?(error, patterns)
        end
      end

      # Extract core message from Liquid error formats:
      #   "Liquid::ArgumentError (templates/foo line 1): invalid integer"
      #   "Liquid::SyntaxError (line 5): unexpected token"
      # Returns just "invalid integer", "unexpected token", etc.
      def extract_core_message(text)
        return text unless text
        if text =~ /\):\s*(.+)$/m
          $1.strip
        elsif text =~ /:\s*(.+)$/m
          $1.strip
        else
          text
        end
      end

      def matches_patterns?(text, patterns)
        return false unless text
        core = extract_core_message(text)
        Array(patterns).all? do |pattern|
          regex = pattern.is_a?(Regexp) ? pattern : /#{Regexp.escape(pattern)}/i
          text.match?(regex) || core.match?(regex)
        end
      end
    end

    # Result of running a single spec
    class SpecResult
      attr_reader :spec, :status, :output, :expected, :reason

      def initialize(spec:, status:, output: nil, expected: nil, reason: nil)
        @spec = spec
        @status = status
        @output = output
        @expected = expected
        @reason = reason
      end

      def passed?
        status == :pass
      end

      def failed?
        status == :fail
      end

      def skipped?
        status == :skipped
      end

      def errored?
        status == :error
      end
    end

    # Aggregate result of running multiple specs
    class RunResult
      attr_reader :adapter, :specs, :results

      def initialize(adapter:, specs:)
        @adapter = adapter
        @specs = specs
        @results = []
      end

      def add(result)
        @results << result
      end

      def passed
        @results.select(&:passed?)
      end

      def failed
        @results.select(&:failed?)
      end

      def skipped
        @results.select(&:skipped?)
      end

      def errors
        @results.select(&:errored?)
      end

      def failures
        failed + errors
      end

      def pass_count
        passed.size
      end

      def fail_count
        failed.size
      end

      def skip_count
        skipped.size
      end

      def error_count
        errors.size
      end

      def total_count
        @results.size
      end

      def success?
        failed.empty? && errors.empty?
      end

      def summary
        "#{pass_count} passed, #{fail_count} failed, #{error_count} errors, #{skip_count} skipped"
      end
    end
  end
end
