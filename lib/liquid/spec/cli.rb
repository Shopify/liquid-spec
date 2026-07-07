# frozen_string_literal: true

require_relative "cli/bench"
require_relative "cli/runner"
require_relative "cli/init"
require_relative "cli/inspect"
require_relative "cli/eval"
require_relative "cli/test"
require_relative "cli/matrix"
require_relative "cli/docs"
require_relative "cli/features"
require_relative "cli/report"

module Liquid
  module Spec
    module CLI
      HELP = <<~HELP
        liquid-spec - Test your Liquid implementation against the official spec

        Usage:
          liquid-spec [command] [options]

        Commands:
          run ADAPTER         Run specs using the specified adapter file
          bench [ADAPTER]     Run benchmarks (all adapters, or ADAPTER vs liquid_ruby)
          test                Run specs against all available example adapters
          matrix              Run specs across multiple adapters and compare results
          report              Analyze and compare benchmark results
          inspect ADAPTER     Inspect specific specs in detail (use with -n PATTERN)
          eval ADAPTER        Quick test a YAML spec against your adapter
          init [FILE]         Generate adapter templates.
                             No FILE: generates both liquid_adapter.rb and
                             liquid_adapter_jsonrpc.rb (executable, self-launching).
                             Flags: --jsonrpc (JSON-RPC), --liquid-ruby (reference)
          features            List available features and their test counts
          docs [NAME]         List or view implementer documentation
          help                Show this help message

        Examples:
          liquid-spec init                              # Creates liquid_adapter.rb
          liquid-spec run adapter.rb                    # Run all specs
          liquid-spec run adapter.rb -n for             # Run specs matching 'for'
          liquid-spec bench                             # Benchmark all builtin adapters
          liquid-spec bench my_adapter.rb               # Benchmark my_adapter vs liquid_ruby
          liquid-spec bench my_adapter.rb -n storefront # Benchmark specific specs
          liquid-spec inspect adapter.rb -n "case.*empty"  # Inspect failing spec
          liquid-spec docs curriculum          # Implementation learning path
          cat spec.yml | liquid-spec eval adapter.rb --compare  # Quick YAML spec test

        Eval Command (quick testing):
          The eval command tests specs from YAML files or stdin:

          # From YAML file
          liquid-spec eval adapter.rb --spec=test.yml

          # From stdin (heredoc)
          cat <<EOF | liquid-spec eval adapter.rb
          name: test_upcase
          hint: "Test upcase filter"
          complexity: 200
          template: "{{ x | upcase }}"
          expected: "HI"
          environment:
            x: hi
          EOF

          # Compare against reference liquid-ruby
          liquid-spec eval adapter.rb --compare < test.yml

          Specs are automatically saved to /tmp/liquid-spec-{date}.yml

        Programmatic API:
          You can also use eval from Ruby code:

            require 'liquid/spec/cli/adapter_dsl'
            LiquidSpec.evaluate("adapter.rb", <<~YAML, compare: true)
              name: test_upcase
              hint: "Test upcase filter"
              complexity: 200
              template: "{{ 'hello' | upcase }}"
              expected: "HELLO"
            YAML

        Implementation Curriculum:
          Start with `liquid-spec docs curriculum`. Specs are ordered by complexity so
          a failing run doubles as a learning path. Complexity is a guide, not an
          architecture mandate: different implementations can choose different internals
          while using the same observable-behavior ramp.

          See also: `liquid-spec docs core-abstractions` and `liquid-spec docs complexity`.

        Run 'liquid-spec <command> --help' for command-specific help.

      HELP

      def self.run(args)
        command = args.shift

        case command
        when "init"
          Init.run(args)
        when "run"
          Runner.run(args)
        when "bench"
          Bench.run(args)
        when "test"
          Test.run(args)
        when "matrix"
          Matrix.run(args)
        when "inspect"
          Inspect.run(args)
        when "eval"
          Eval.run(args)
        when "docs"
          Docs.run(args)
        when "features"
          Features.run(args)
        when "report"
          Report.run(args)
        when "help", "-h", "--help", nil
          puts HELP
        else
          # If first arg looks like a file, treat it as 'run'
          if File.exist?(command) || command.end_with?(".rb")
            Runner.run([command] + args)
          else
            $stderr.puts "Unknown command: #{command}"
            $stderr.puts "Run 'liquid-spec help' for usage"
            exit(1)
          end
        end
      end
    end
  end
end
