# frozen_string_literal: true

require "stringio"

lib_dir = File.expand_path("../..", __dir__)
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

module Liquid
  module Spec
    # Loads and executes every verifier in scripts/verifiers. Verifier scripts
    # remain independently executable; this runner provides the shared CLI and
    # Rake entry point without duplicating discovery or advisory semantics.
    module Verifiers
      VERIFIER_MODULES = {
        "cross_mode_compatibility" => "CrossModeCompatibilityVerifier",
        "filesystem_extensions" => "FilesystemExtensionVerifier",
        "jsonrpc_portability" => "JsonRpcPortabilityVerifier",
        "lax_mode_declared" => "LaxModeDeclaredVerifier",
        "lax_placement" => "LaxPlacementVerifier",
        "minimum_complexity" => "MinimumComplexityVerifier",
        "parse_mode_annotation" => "ParseModeAnnotationVerifier",
        "ruby_type_tags" => "RubyTypeTagVerifier",
        "spec_name_collisions" => "SpecNameCollisionVerifier",
        "spec_schema" => "SpecSchemaVerifier",
      }.freeze

      Result = Struct.new(:name, :exit_code, :advisory, keyword_init: true)

      class << self
        def run(verifiers_dir: default_verifiers_dir, output: $stdout, error: $stderr)
          results = discover(verifiers_dir).map do |script|
            run_verifier(script, output: output, error: error)
          end

          print_summary(results, output: output)
          results.any? { |result| result.exit_code != 0 && !result.advisory } ? 1 : 0
        end

        def default_verifiers_dir
          File.expand_path("../../../scripts/verifiers", __dir__)
        end

        private

        def discover(verifiers_dir)
          scripts = Dir.glob(File.join(verifiers_dir, "*.rb")).sort
          raise ArgumentError, "No verifiers found in #{verifiers_dir}" if scripts.empty?
          scripts
        end

        def run_verifier(script, output:, error:)
          name = File.basename(script, ".rb")
          advisory = File.read(script, 500).include?("advisory: true")
          module_name = VERIFIER_MODULES[name]

          unless module_name
            error.puts "ERROR: verifier #{name}.rb is not registered in Liquid::Spec::Verifiers"
            return Result.new(name: name, exit_code: 1, advisory: false)
          end

          load(script)
          unless Object.const_defined?(module_name)
            error.puts "ERROR: verifier #{name}.rb did not define #{module_name}"
            return Result.new(name: name, exit_code: 1, advisory: false)
          end

          verifier = Object.const_get(module_name)
          captured = StringIO.new
          exit_code = capture_stdout(captured) { verifier.run }
          cleaned = clean_output(captured.string)
          output.puts cleaned unless cleaned.empty?

          Result.new(name: name, exit_code: exit_code || 0, advisory: advisory)
        rescue SystemExit => system_exit
          error.puts "ERROR: verifier #{name}.rb called exit; return an exit code instead"
          Result.new(name: name, exit_code: system_exit.status.nonzero? || 1, advisory: false)
        rescue StandardError => exception
          error.puts "ERROR: verifier #{name}.rb crashed: #{exception.class}: #{exception.message}"
          Result.new(name: name, exit_code: 1, advisory: false)
        end

        def capture_stdout(stream)
          original_stdout = $stdout
          $stdout = stream
          yield
        ensure
          $stdout = original_stdout
        end

        def clean_output(text)
          text.gsub(/\r/, "\n").lines.reject do |line|
            line.strip.match?(/\ATesting spec \d+\/\d+/)
          end.join
        end

        def print_summary(results, output:)
          output.puts "=" * 60
          output.puts "Check summary:"
          output.puts "=" * 60

          results.each do |result|
            status = if result.exit_code.zero?
              "PASS"
            elsif result.advisory
              "ADVISORY"
            else
              "FAIL"
            end
            output.puts "  #{status}  #{result.name}"
          end

          failures = results.count { |result| result.exit_code != 0 && !result.advisory }
          if failures.zero?
            advisory_count = results.count { |result| result.advisory && result.exit_code != 0 }
            suffix = if advisory_count.positive?
              " (#{advisory_count} advisory check(s) have findings — see output above)"
            else
              ""
            end
            output.puts "\nAll #{results.size} checks passed#{suffix}."
          else
            output.puts "\n#{failures} of #{results.size} checks failed."
          end
        end
      end
    end
  end
end
