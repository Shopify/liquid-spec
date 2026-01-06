# frozen_string_literal: true

require_relative "cli/runner"
require_relative "cli/init"
require_relative "cli/inspect"
require_relative "cli/eval"
require_relative "cli/test"
require_relative "cli/matrix"
require_relative "cli/docs"

module Liquid
  module Spec
    module CLI
      HELP = <<~HELP
        liquid-spec - Test your Liquid implementation against the official spec

        Usage:
          liquid-spec [command] [options]

        Commands:
          run ADAPTER         Run specs using the specified adapter file
          test                Run specs against all available example adapters
          matrix              Run specs across multiple adapters and compare results
          inspect ADAPTER     Inspect specific specs in detail (use with -n PATTERN)
          eval ADAPTER        Quick test a template against your adapter
          init [FILE]         Generate an adapter template (default: liquid_adapter.rb)
          docs [NAME]         List or view implementer documentation
          help                Show this help message

        Examples:
          liquid-spec init                              # Creates liquid_adapter.rb
          liquid-spec run adapter.rb                    # Run all specs
          liquid-spec run adapter.rb -n for             # Run specs matching 'for'
          liquid-spec inspect adapter.rb -n "case.*empty"  # Inspect failing spec
          liquid-spec eval adapter.rb -l "{{ 'hi' | upcase }}"  # Quick test

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

        Complexity Scoring (see COMPLEXITY.md for full guide):
          Specs have a complexity score indicating implementation difficulty.
          Lower = simpler features to implement first.

          Range     Feature
          -----     -------
          10-20     Literals, raw text output
          30-50     Variables, filters, assign
          55-60     Whitespace control, if/else/unless
          70-80     For loops, operators, filter chains
          85-100    Math filters, forloop object, capture, case/when
          105-130   String filters, increment, comment, raw, echo, liquid tag
          140-180   Array filters, property access, truthy/falsy, cycle, tablerow
          190-220   Advanced: offset:continue, parentloop, partials
          300-500   Edge cases, deprecated features
          1000+     Production recordings, unscored specs (default)

        Run 'liquid-spec <command> --help' for command-specific help.

      HELP

      def self.run(args)
        command = args.shift

        case command
        when "init"
          Init.run(args)
        when "run"
          Runner.run(args)
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
