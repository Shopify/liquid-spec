# frozen_string_literal: true

require "json"
require "time"
require_relative "../adversarial"

module Liquid
  module Spec
    module CLI
      # CLI front-end for deterministic mutation, randomized differential
      # fuzz-style testing, and bounded structural stress generation.
      module Adversarial
        HELP = <<~HELP
          Usage:
            liquid-spec tools mutate ADAPTER [options]
            liquid-spec tools fuzz ADAPTER [options]
            liquid-spec tools stress ADAPTER [options]

          Generate Liquid cases from the existing spec corpus and compare the
          adapter against Shopify/liquid. This is differential corpus mutation,
          not coverage-guided native fuzzing.

          Modes:
            mutate   Deterministically enumerate attributable template mutations
            fuzz     Randomly chain mutations; always prints the reproduction seed
            stress   Generate bounded valid nesting and repetition cases

          Options:
            --around=TOPIC         Select seed specs related to a name/topic (e.g. for_loops)
            -n, --name=PATTERN     Select seed specs by name regexp
            --suite=SUITE          Select a suite (default: all default suites)
            --features=LIST        Require comma-separated feature tags on seeds
            --reference=ADAPTER    Reference adapter (default: examples/liquid_ruby.rb)
            --command=CMD          Subject JSON-RPC server command
            --timeout=SECONDS      Per generated case and JSON-RPC timeout (default: 2)
            --seed=N               Reproduction seed (mutate/stress default: 1)
            --limit=N              Maximum generated cases (default: 100; stress: 10)
            --rounds=N             Fuzz generation attempts (default: limit * 5)
            --save=DIR             Save discrepancies as runnable YAML regression specs
            --no-save              Do not save discrepancies (default saves under /tmp)
            --minimize             Best-effort minimize discrepancies before saving
            --minimize-budget=N    Maximum minimizer attempts per discrepancy (default: 40)
            --depth=N              Stress nesting depth (default: 32)
            --repetitions=N        Stress template repetitions (default: 32)
            --json                 Print one machine-readable summary object
            -h, --help             Show this help

          Exit codes:
            0  No differential discrepancies found
            1  One or more discrepancies found
            2  Invalid command/configuration or adapter setup failed

          Examples:
            liquid-spec tools mutate adapter.rb --around=for_loops --limit=100
            liquid-spec tools fuzz adapter.rb --seed=1234 --rounds=500 --minimize
            liquid-spec tools stress adapter.rb --depth=64 --repetitions=100

          Saved files contain reference expectations and can be run later with:
            liquid-spec run adapter.rb --add-specs='tmp/regressions/*.yml'
        HELP

        class << self
          def run(args, mode:)
            if args.empty? || args.include?("-h") || args.include?("--help")
              puts HELP
              return
            end

            adapter = args.shift
            options = parse_options(args, mode)
            unless File.exist?(adapter)
              $stderr.puts "Error: Adapter file not found: #{adapter}"
              exit(2)
            end

            summary = execute(adapter, mode: mode, **options)
            options[:json] ? print_json(summary) : print_summary(summary, options)
            exit(1) unless summary.success?
          rescue ArgumentError => error
            $stderr.puts "Error: #{error.message}"
            exit(2)
          end

          def execute(adapter, mode:, **options)
            engine_options = options.reject { |key, _| [:json].include?(key) }
            Liquid::Spec::Adversarial::Engine.new(
              adapter: adapter,
              mode: mode,
              **engine_options,
            ).run
          end

          def parse_options(args, mode)
            options = {
              seed: mode == :fuzz ? Random.new_seed : 1,
              limit: mode == :stress ? 10 : 100,
              timeout: 2,
              minimize: false,
              minimize_budget: 40,
              depth: 32,
              repetitions: 32,
              features: [],
              save_dir: default_save_dir(mode),
              json: false,
            }

            while args.any?
              arg = args.shift
              case arg
              when "--compare"
                # Differential comparison is always enabled; accepted for clarity.
              when "--around"
                options[:around] = require_value(arg, args.shift)
              when /\A--around=(.+)\z/
                options[:around] = ::Regexp.last_match(1)
              when "-n", "--name"
                options[:name] = require_value(arg, args.shift)
              when /\A--name=(.+)\z/
                options[:name] = ::Regexp.last_match(1)
              when "--suite"
                options[:suite] = require_value(arg, args.shift).to_sym
              when /\A--suite=(.+)\z/
                options[:suite] = ::Regexp.last_match(1).to_sym
              when "--features"
                options[:features] = csv(require_value(arg, args.shift))
              when /\A--features=(.+)\z/
                options[:features] = csv(::Regexp.last_match(1))
              when "--reference"
                options[:reference] = require_value(arg, args.shift)
              when /\A--reference=(.+)\z/
                options[:reference] = ::Regexp.last_match(1)
              when "--command"
                options[:command] = require_value(arg, args.shift)
              when /\A--command=(.+)\z/
                options[:command] = ::Regexp.last_match(1)
              when "--timeout"
                options[:timeout] = positive_number(arg, args.shift)
              when /\A--timeout=(.+)\z/
                options[:timeout] = positive_number("--timeout", ::Regexp.last_match(1))
              when "--seed"
                options[:seed] = integer(arg, args.shift, minimum: 0)
              when /\A--seed=(\d+)\z/
                options[:seed] = ::Regexp.last_match(1).to_i
              when "--limit"
                options[:limit] = integer(arg, args.shift, minimum: 1)
              when /\A--limit=(\d+)\z/
                options[:limit] = positive_integer("--limit", ::Regexp.last_match(1))
              when "--rounds"
                options[:rounds] = integer(arg, args.shift, minimum: 1)
              when /\A--rounds=(\d+)\z/
                options[:rounds] = positive_integer("--rounds", ::Regexp.last_match(1))
              when "--save"
                options[:save_dir] = require_value(arg, args.shift)
              when /\A--save=(.+)\z/
                options[:save_dir] = ::Regexp.last_match(1)
              when "--no-save"
                options[:save_dir] = nil
              when "--minimize"
                options[:minimize] = true
              when "--no-minimize"
                options[:minimize] = false
              when "--minimize-budget"
                options[:minimize_budget] = integer(arg, args.shift, minimum: 1)
              when /\A--minimize-budget=(\d+)\z/
                options[:minimize_budget] = positive_integer("--minimize-budget", ::Regexp.last_match(1))
              when "--depth"
                options[:depth] = integer(arg, args.shift, minimum: 1)
              when /\A--depth=(\d+)\z/
                options[:depth] = positive_integer("--depth", ::Regexp.last_match(1))
              when "--repetitions"
                options[:repetitions] = integer(arg, args.shift, minimum: 1)
              when /\A--repetitions=(\d+)\z/
                options[:repetitions] = positive_integer("--repetitions", ::Regexp.last_match(1))
              when "--json"
                options[:json] = true
              else
                raise ArgumentError, "Unknown option: #{arg}"
              end
            end

            options
          end

          private

          def default_save_dir(mode)
            timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
            "/tmp/liquid-spec-#{mode}-#{timestamp}"
          end

          def require_value(option, value)
            raise ArgumentError, "#{option} requires a value" if value.nil? || value.start_with?("-")
            value
          end

          def csv(value)
            value.split(",").map(&:strip).reject(&:empty?).map(&:to_sym)
          end

          def integer(option, value, minimum:)
            value = require_value(option, value)
            parsed = Integer(value, 10)
            raise ArgumentError, "#{option} must be >= #{minimum}" if parsed < minimum
            parsed
          rescue ArgumentError => error
            raise error if error.message.start_with?(option)
            raise ArgumentError, "#{option} must be an integer >= #{minimum}"
          end

          def positive_integer(option, value)
            parsed = value.to_i
            raise ArgumentError, "#{option} must be an integer >= 1" if parsed < 1
            parsed
          end

          def positive_number(option, value)
            value = require_value(option, value)
            parsed = Float(value)
            raise ArgumentError, "#{option} must be > 0" unless parsed.positive?
            parsed
          rescue ArgumentError => error
            raise error if error.message.start_with?(option)
            raise ArgumentError, "#{option} must be a number > 0"
          end

          def print_json(summary)
            puts JSON.pretty_generate(summary.to_h)
          end

          def print_summary(summary, options)
            puts "Generated differential #{summary.mode}"
            puts "Seed: #{summary.seed}"
            puts "Generated: #{summary.generated}, executed: #{summary.executed}, " \
              "passed: #{summary.passed}, discrepancies: #{summary.findings.length}, " \
              "skipped: #{summary.skipped}"

            if summary.findings.empty?
              puts "\nNo differences found."
              return
            end

            puts "\nDifferential discrepancies:"
            summary.findings.each_with_index do |finding, index|
              puts "\n#{index + 1}) [#{finding.classification}] #{finding.case.spec.name}"
              puts "   Parent:    #{finding.case.parent.name} (#{finding.case.parent.location})"
              puts "   Mutations: #{finding.case.mutations.map(&:id).join(", ")}"
              puts "   Template:  #{finding.case.spec.template.inspect}"
              puts "   Reference: #{format_outcome(finding.reference)}"
              puts "   Subject:   #{format_outcome(finding.subject)}"
              puts "   Saved:     #{finding.saved_to}" if finding.saved_to
            end

            puts "\nReproduce with seed #{summary.seed}."
            puts "Saved regression specs under: #{options[:save_dir]}" if options[:save_dir]
          end

          def format_outcome(outcome)
            if outcome.status == :ok
              "output #{outcome.output.inspect}"
            else
              [outcome.status, outcome.error_category, outcome.error_message].compact.join(": ")
            end
          end
        end
      end
    end
  end
end
