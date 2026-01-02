# frozen_string_literal: true

require_relative "cli/runner"
require_relative "cli/init"
require_relative "cli/inspect"
require_relative "cli/eval"

module Liquid
  module Spec
    module CLI
      HELP = <<~HELP
        liquid-spec - Test your Liquid implementation against the official spec

        Usage:
          liquid-spec [command] [options]

        Commands:
          run ADAPTER         Run specs using the specified adapter file
          inspect ADAPTER     Inspect specific specs in detail (use with -n PATTERN)
          eval ADAPTER        Quick test a template against your adapter
          init [FILE]         Generate an adapter template (default: liquid_adapter.rb)
          help                Show this help message

        Examples:
          liquid-spec init                              # Creates liquid_adapter.rb
          liquid-spec run adapter.rb                    # Run all specs
          liquid-spec run adapter.rb -n for             # Run specs matching 'for'
          liquid-spec inspect adapter.rb -n "case.*empty"  # Inspect failing spec
          liquid-spec eval adapter.rb -l "{{ 'hi' | upcase }}"  # Quick test

        Run 'liquid-spec <command> --help' for command-specific help.

      HELP

      def self.run(args)
        command = args.shift

        case command
        when "init"
          Init.run(args)
        when "run"
          Runner.run(args)
        when "inspect"
          Inspect.run(args)
        when "eval"
          Eval.run(args)
        when "help", "-h", "--help", nil
          puts HELP
        else
          # If first arg looks like a file, treat it as 'run'
          if File.exist?(command) || command.end_with?(".rb")
            Runner.run([command] + args)
          else
            $stderr.puts "Unknown command: #{command}"
            $stderr.puts "Run 'liquid-spec help' for usage"
            exit 1
          end
        end
      end
    end
  end
end
