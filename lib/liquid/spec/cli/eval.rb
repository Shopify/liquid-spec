# frozen_string_literal: true

require_relative "adapter_dsl"

module Liquid
  module Spec
    module CLI
      # Eval command - quick test of a template against an adapter
      module Eval
        HELP = <<~HELP
          Usage: liquid-spec eval ADAPTER --liquid="TEMPLATE" [options]
                 liquid-spec eval ADAPTER --spec=FILE.yml [options]

          Quickly test a Liquid template against your adapter.

          Options:
            -l, --liquid TEMPLATE   The Liquid template to render
            -s, --spec FILE.yml     Load test from a YAML spec file
            -e, --expected OUTPUT   Expected output (for pass/fail check)
            -a, --assigns JSON      JSON object of assigns/environment
            -v, --verbose           Show detailed output
            -h, --help              Show this help

          Examples:
            liquid-spec eval my_adapter.rb --liquid="{{ 'hello' | upcase }}"
            liquid-spec eval my_adapter.rb -l "{{ x }}" -a '{"x": 42}'
            liquid-spec eval my_adapter.rb -l "{{ x }}" -a '{"x": 42}' -e "42"
            liquid-spec eval my_adapter.rb --spec=my_test.yml

          Spec file format (YAML):
            template: "{{ x | upcase }}"
            expected: "HELLO"
            environment:
              x: hello

        HELP

        def self.run(args)
          if args.empty? || args.include?("-h") || args.include?("--help")
            puts HELP
            return
          end

          adapter_file = args.shift
          options = parse_options(args)

          unless options[:liquid] || options[:spec_file]
            $stderr.puts "Error: --liquid TEMPLATE or --spec FILE is required"
            $stderr.puts "Run 'liquid-spec eval --help' for usage"
            exit 1
          end

          unless File.exist?(adapter_file)
            $stderr.puts "Error: Adapter file not found: #{adapter_file}"
            exit 1
          end

          # Load the adapter
          LiquidSpec.reset!
          LiquidSpec.running_from_cli!
          load File.expand_path(adapter_file)

          run_eval(options)
        end

        def self.parse_options(args)
          options = { assigns: {} }

          while args.any?
            arg = args.shift
            case arg
            when "-l", "--liquid"
              options[:liquid] = args.shift
            when /\A--liquid=(.+)\z/
              options[:liquid] = $1
            when "-s", "--spec"
              options[:spec_file] = args.shift
            when /\A--spec=(.+)\z/
              options[:spec_file] = $1
            when "-e", "--expected"
              options[:expected] = args.shift
            when /\A--expected=(.+)\z/
              options[:expected] = $1
            when "-a", "--assigns"
              require "json"
              options[:assigns] = JSON.parse(args.shift)
            when /\A--assigns=(.+)\z/
              require "json"
              options[:assigns] = JSON.parse($1)
            when "-v", "--verbose"
              options[:verbose] = true
            end
          end

          options
        end

        def self.run_eval(options)
          # Run setup
          LiquidSpec.run_setup!

          # Load from spec file if provided
          if options[:spec_file]
            load_spec_file(options)
            puts ""
            puts "Please contribute your tests at https://github.com/Shopify/liquid-spec!"
            puts ""
          end

          template_source = options[:liquid]
          assigns = options[:assigns]
          expected = options[:expected]
          verbose = options[:verbose]

          puts "TEMPLATE: #{template_source.inspect}" if verbose

          begin
            # Compile
            template = LiquidSpec.do_compile(template_source, { line_numbers: true })

            if verbose && template.respond_to?(:source)
              puts "\nGENERATED CODE:"
              puts template.source
            end

            # Build minimal context
            # We need to load Liquid to get access to context classes
            context_klass = defined?(Liquid::Context) ? Liquid::Context : nil

            ctx = {
              environment: assigns,
              file_system: nil,
              template_factory: nil,
              exception_renderer: nil,
              error_mode: nil,
              render_errors: false,
              context_klass: context_klass,
            }

            # Render
            actual = LiquidSpec.do_render(template, ctx)

            puts "\nOUTPUT:"
            puts actual.inspect
            puts actual

            if expected
              puts "\nEXPECTED:"
              puts expected.inspect

              if actual == expected
                puts "\nSTATUS: PASS"
              else
                puts "\nSTATUS: FAIL"
                exit 1
              end
            end
          rescue => e
            puts "\nERROR: #{e.class}: #{e.message}"
            puts e.backtrace.first(10).join("\n") if verbose
            exit 1
          end
        end

        def self.load_spec_file(options)
          require "yaml"

          spec_file = options[:spec_file]
          unless File.exist?(spec_file)
            $stderr.puts "Error: Spec file not found: #{spec_file}"
            exit 1
          end

          spec = YAML.safe_load(File.read(spec_file), permitted_classes: [Symbol])

          options[:liquid] = spec["template"] || spec[:template]
          options[:expected] = spec["expected"] || spec[:expected] if spec.key?("expected") || spec.key?(:expected)
          options[:assigns] = spec["environment"] || spec[:environment] || spec["assigns"] || spec[:assigns] || {}

          unless options[:liquid]
            $stderr.puts "Error: Spec file must contain 'template' key"
            exit 1
          end
        end
      end
    end
  end
end
