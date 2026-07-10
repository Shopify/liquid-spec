# frozen_string_literal: true

require_relative "adversarial"
require_relative "check"
require_relative "eval"
require_relative "features"
require_relative "inspect"
require_relative "matrix"
require_relative "report"
require_relative "test"

module Liquid
  module Spec
    module CLI
      # Secondary development, inspection, comparison, and generation tools.
      # The top-level CLI stays focused on init/docs/run/bench.
      module Tools
        HELP = <<~HELP
          liquid-spec tools - Development and analysis utilities

          Usage:
            liquid-spec tools COMMAND [options]

          Commands:
            inspect ADAPTER     Inspect matching specs and adapter output
            eval ADAPTER        Evaluate one YAML spec against an adapter/reference
            matrix              Compare multiple adapters side-by-side
            test                Run specs against bundled example adapters
            features            List feature tags, counts, and recommendations
            report              Analyze stored benchmark results
            check               Run every spec verifier
            mutate ADAPTER      Deterministic differential corpus mutations
            fuzz ADAPTER        Seeded differential fuzz-style testing
            stress ADAPTER      Bounded differential nesting/repetition stress

          Examples:
            liquid-spec tools inspect adapter.rb -n "case.*empty"
            cat spec.yml | liquid-spec tools eval adapter.rb --compare
            liquid-spec tools matrix --all
            liquid-spec tools check
            liquid-spec tools mutate adapter.rb --around=for_loops
            liquid-spec tools fuzz adapter.rb --seed=1234

          Run `liquid-spec tools COMMAND --help` for command-specific help.
        HELP

        class << self
          def run(args)
            command = args.shift

            case command
            when "inspect"
              Inspect.run(args)
            when "eval"
              Eval.run(args)
            when "matrix"
              Matrix.run(args)
            when "test"
              Test.run(args)
            when "features"
              Features.run(args)
            when "report"
              Report.run(args)
            when "check"
              Check.run(args)
            when "mutate"
              Adversarial.run(args, mode: :mutate)
            when "fuzz"
              Adversarial.run(args, mode: :fuzz)
            when "stress"
              Adversarial.run(args, mode: :stress)
            when "help", "-h", "--help", nil
              puts HELP
            else
              $stderr.puts "Unknown tools command: #{command}"
              $stderr.puts "Run 'liquid-spec tools help' for usage"
              exit(1)
            end
          end
        end
      end
    end
  end
end
