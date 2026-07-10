# frozen_string_literal: true

require_relative "cli/bench"
require_relative "cli/docs"
require_relative "cli/init"
require_relative "cli/runner"
require_relative "cli/tools"

module Liquid
  module Spec
    module CLI
      HELP = <<~HELP
        liquid-spec - Build and verify Liquid implementations

        Usage:
          liquid-spec COMMAND [options]

        Core commands:
          init [FILE]         Generate adapters and AGENTS.md implementation guidance
          docs [NAME]         Read the implementation curriculum and semantic guides
          run ADAPTER         Run the acceptance ramp against an implementation
          bench [ADAPTER]     Benchmark one or more implementations

        Additional tools:
          tools COMMAND       Inspection, eval, matrix, feature, verifier, and
                              generated adversarial utilities

        Other:
          help                Show this help

        Start a new implementation:
          liquid-spec init
          liquid-spec docs curriculum
          liquid-spec run specs/adapter.rb

        Non-Ruby implementation:
          liquid-spec init --jsonrpc
          liquid-spec run specs/adapter-jsonrpc.rb --command="./my-liquid-server"

        Explore the tool collection:
          liquid-spec tools help
          liquid-spec tools inspect adapter.rb -n "case.*empty"
          cat spec.yml | liquid-spec tools eval adapter.rb --compare
          liquid-spec tools check

        Backward compatibility:
          `liquid-spec ADAPTER` remains shorthand for `liquid-spec run ADAPTER`.
          Former top-level utility commands remain temporary deprecated aliases
          under their new `liquid-spec tools ...` names.

        Run `liquid-spec COMMAND --help` or `liquid-spec tools COMMAND --help`
        for command-specific help.
      HELP

      LEGACY_TOOL_COMMANDS = %w[
        eval features fuzz inspect matrix mutate report stress test
      ].freeze

      def self.run(args)
        command = args.shift

        case command
        when "init"
          Init.run(args)
        when "docs"
          Docs.run(args)
        when "run"
          Runner.run(args)
        when "bench"
          Bench.run(args)
        when "tools"
          Tools.run(args)
        when "help", "-h", "--help", nil
          puts HELP
        else
          if LEGACY_TOOL_COMMANDS.include?(command)
            warn "Deprecated: use `liquid-spec tools #{command}` instead."
            Tools.run([command] + args)
          # If first arg looks like a file, treat it as `run`.
          elsif File.exist?(command) || command.end_with?(".rb")
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
