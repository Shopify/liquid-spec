# frozen_string_literal: true

require_relative "benchmark"
require_relative "config"
require_relative "runs"

module Liquid
  module Spec
    module CLI
      # `liquid-spec bench` — run benchmarks sequentially with nice per-spec output.
      #
      # - `liquid-spec bench`              → all builtin adapters, one after another
      # - `liquid-spec bench my_adapter.rb` → my_adapter vs liquid_ruby
      # - `liquid-spec bench my_adapter.rb -n storefront` → filtered
      #
      # Each adapter runs as a subprocess with full hyperfine-style output.
      # If multiple adapters, a comparison summary is shown at the end.
      module Bench
        HELP = <<~HELP
          Usage: liquid-spec bench [ADAPTER] [options]

          Run benchmarks with hyperfine-style output.

          With no adapter:    runs all builtin adapters sequentially
          With an adapter:    runs ADAPTER vs liquid_ruby (reference)

          Options:
            -n, --name PATTERN    Filter specs by name pattern
            -s, --suite SUITE     Spec suite (default: benchmarks)
            --all                 Run all builtin adapters
            --adapter=PATH        Add a specific adapter
            --adapters=LIST       Comma-separated adapter list
            -v, --verbose         Verbose output
            -h, --help            Show this help

          Examples:
            liquid-spec bench
            liquid-spec bench my_adapter.rb
            liquid-spec bench my_adapter.rb -n storefront
            liquid-spec bench --adapters=liquid_ruby,liquid_c
        HELP

        class << self
          def run(args)
            if args.include?("-h") || args.include?("--help")
              puts HELP
              return
            end

            # Parse adapter options via Runs
            runs = Runs.new
            runs.parse_options!(args)

            # Check if first remaining arg is an adapter file
            if args.first && !args.first.start_with?("-") &&
               (File.exist?(args.first) || File.exist?("#{args.first}.rb") || args.first.end_with?(".rb"))
              adapter_path = args.shift
              runs.add_adapter("liquid_ruby")  # reference first
              runs.add_adapter(adapter_path)
            end

            # Default to --all if no adapters specified
            runs.add_all_builtin_adapters if runs.empty?

            # Collect remaining flags to pass through
            pass_through = args.dup

            # Single adapter: just run it directly (in-process, no subprocess)
            if runs.adapters.size == 1
              adapter = runs.adapters.first
              cmd = build_cmd(adapter.path, pass_through)
              exec_adapter(cmd)
              return
            end

            # Multiple adapters: run each sequentially, collect JSONL for comparison
            reports_dir = runs.reports_dir
            results_by_adapter = {}

            runs.adapters.each do |adapter|
              cmd = build_cmd(adapter.path, pass_through)
              jsonl_path = File.join(reports_dir, "#{adapter.name}.jsonl")

              # Run with normal output (nice per-spec display) + tee JSONL
              env = { "LIQUID_SPEC_RUN_ID" => Config.generate_run_id }
              system(env, *cmd)

              # Read back results for comparison
              if File.exist?(jsonl_path)
                results_by_adapter[adapter.name] = File.readlines(jsonl_path).filter_map do |line|
                  data = JSON.parse(line, symbolize_names: true) rescue nil
                  data if data && data[:type] == "result" && data[:status] == "success"
                end
              end
            end

            # Show cross-adapter comparison
            if results_by_adapter.size >= 2
              puts ""
              print_comparison(runs.adapter_names, results_by_adapter)
            end
          end

          private

          def build_cmd(adapter_path, extra_args)
            gem_root = File.expand_path("../../../../..", __FILE__)
            cmd = ["bundle", "exec", "ruby", "-Ilib", "bin/liquid-spec",
                   "run", adapter_path, "-s", "benchmarks", "--bench"]
            cmd += extra_args
            cmd
          end

          def exec_adapter(cmd)
            gem_root = File.expand_path("../../../../..", __FILE__)
            Dir.chdir(gem_root) { system(*cmd) }
          end

          def print_comparison(adapter_names, results_by_adapter)
            f = Benchmark.method(:fmt)
            reference = adapter_names.first
            others = adapter_names[1..]

            # Find common specs
            all_specs = results_by_adapter.values.map { |rs| rs.map { |r| r[:spec_name] } }
            common = all_specs.reduce(:&) || []
            return if common.empty?

            puts "─" * 70
            puts "\e[1mComparison\e[0m (#{common.size} common specs, reference: #{reference})"
            puts ""

            parse_ratios = Hash.new { |h, k| h[k] = [] }
            render_ratios = Hash.new { |h, k| h[k] = [] }

            common.each do |spec_name|
              ref = results_by_adapter[reference]&.find { |r| r[:spec_name] == spec_name }
              next unless ref

              ref_parse  = ref[:parse_mean] || ref[:compile_mean]
              ref_render = ref[:render_mean]

              others.each do |other|
                o = results_by_adapter[other]&.find { |r| r[:spec_name] == spec_name }
                next unless o

                o_parse  = o[:parse_mean] || o[:compile_mean]
                o_render = o[:render_mean]

                parse_ratios[other]  << o_parse / ref_parse   if ref_parse  && o_parse  && ref_parse  > 0
                render_ratios[other] << o_render / ref_render if ref_render && o_render && ref_render > 0
              end
            end

            puts "  \e[1mParse (geometric mean):\e[0m"
            others.each do |adapter|
              ratios = parse_ratios[adapter]
              next if ratios.empty?
              gm = geometric_mean(ratios)
              if gm > 1.05
                puts "    \e[32m#{reference}\e[0m is \e[1;32m%.2fx faster\e[0m than #{adapter}" % gm
              elsif gm < 0.95
                puts "    \e[32m#{adapter}\e[0m is \e[1;32m%.2fx faster\e[0m than #{reference}" % (1.0 / gm)
              else
                puts "    #{adapter} ≈ #{reference}"
              end
            end

            puts "  \e[1mRender (geometric mean):\e[0m"
            others.each do |adapter|
              ratios = render_ratios[adapter]
              next if ratios.empty?
              gm = geometric_mean(ratios)
              if gm > 1.05
                puts "    \e[32m#{reference}\e[0m is \e[1;32m%.2fx faster\e[0m than #{adapter}" % gm
              elsif gm < 0.95
                puts "    \e[32m#{adapter}\e[0m is \e[1;32m%.2fx faster\e[0m than #{reference}" % (1.0 / gm)
              else
                puts "    #{adapter} ≈ #{reference}"
              end
            end

            puts ""
          end

          def geometric_mean(arr)
            return 0 if arr.empty?
            (arr.reduce(1.0) { |prod, x| prod * x })**(1.0 / arr.size)
          end
        end
      end
    end
  end
end
