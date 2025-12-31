# frozen_string_literal: true

require_relative "cli/runner"
require_relative "cli/init"

module Liquid
  module Spec
    module CLI
      HELP = <<~HELP
        liquid-spec - Test your Liquid implementation against the official spec

        Usage:
          liquid-spec [command] [options]

        Commands:
          init [FILE]     Generate an adapter template (default: liquid_adapter.rb)
          run ADAPTER     Run specs using the specified adapter file
          help            Show this help message

        Examples:
          liquid-spec init                    # Creates liquid_adapter.rb
          liquid-spec init my_adapter.rb     # Creates my_adapter.rb
          liquid-spec run liquid_adapter.rb  # Run all specs
          liquid-spec run adapter.rb -n for  # Run specs matching 'for'
          liquid-spec run adapter.rb -s liquid_ruby  # Run only liquid_ruby specs

        Options for 'run':
          -n, --name PATTERN    Only run specs matching PATTERN
          -s, --suite SUITE     Spec suite: all, liquid_ruby, dawn (default: all)
          -v, --verbose         Show verbose output
          -h, --help            Show help for command

      HELP

      def self.run(args)
        command = args.shift

        case command
        when "init"
          Init.run(args)
        when "run"
          Runner.run(args)
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
