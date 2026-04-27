# frozen_string_literal: true

require "fileutils"

module Liquid
  module Spec
    module CLI
      # Centralized configuration for liquid-spec CLI
      module Config
        DEFAULT_REPORTS_DIR = "/tmp/liquid-spec"

        class << self
          # Returns the directory for storing benchmark/run reports
          # Checks LIQUID_SPEC_REPORTS env var first, then falls back to default
          #
          # @param output_override [String, nil] CLI-specified output directory (-o option)
          # @return [String] Path to reports directory
          def reports_dir(output_override = nil)
            dir = output_override || ENV["LIQUID_SPEC_REPORTS"] || DEFAULT_REPORTS_DIR
            FileUtils.mkdir_p(dir)
            dir
          end

          # Path to JSONL file for a specific adapter run.
          # Each run gets its own file: {adapter}.{timestamp}.jsonl
          #
          # @param adapter_name [String] The adapter name (e.g., "liquid_ruby")
          # @param run_id [String] Run ID / timestamp (e.g., "20260319_004500")
          # @param output_override [String, nil] CLI-specified output directory
          # @return [String] Full path to the adapter's JSONL file
          def adapter_jsonl_path(adapter_name, run_id: nil, output_override: nil)
            run_id ||= generate_run_id
            File.join(reports_dir(output_override), "#{adapter_name}.#{run_id}.jsonl")
          end

          # Returns JIT information for the current Ruby process
          #
          # @return [Hash] { enabled: Boolean, engine: String }
          def jit_info
            if defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?
              { enabled: true, engine: "zjit" }
            elsif defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
              { enabled: true, engine: "yjit" }
            else
              { enabled: false, engine: "none" }
            end
          end

          # Returns the current time, bypassing any time freezing
          #
          # @return [Time] Real wall-clock time
          def real_time
            Process.clock_gettime(Process::CLOCK_REALTIME).then { |t| Time.at(t) }
          end

          # Generate a unique run ID
          #
          # @return [String] Run ID in format YYYYMMDD_HHMMSS
          def generate_run_id
            real_time.strftime("%Y%m%d_%H%M%S")
          end
        end
      end
    end
  end
end
