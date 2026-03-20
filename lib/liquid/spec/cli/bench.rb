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

            # Consume positional adapter file arguments
            positional_adapters = []
            while args.first && !args.first.start_with?("-") &&
                  (File.exist?(args.first) || File.exist?("#{args.first}.rb") || args.first.end_with?(".rb"))
              positional_adapters << args.shift
            end

            if positional_adapters.size == 1
              # Single adapter: add liquid_ruby as reference first
              runs.add_adapter("liquid_ruby")
              runs.add_adapter(positional_adapters.first)
            elsif positional_adapters.size >= 2
              # Multiple adapters: use them as-is (first is reference)
              positional_adapters.each { |a| runs.add_adapter(a) }
            end

            # Catch --json mistake
            if args.include?("--json")
              $stderr.puts "Error: Use --jsonl (not --json). Output is JSON Lines (one object per line)."
              exit(1)
            end

            # Default to --all if no adapters specified
            runs.add_all_builtin_adapters if runs.empty?

            # Extract --jsonl (don't pass to subprocesses — they always write files)
            jsonl_mode = args.delete("--jsonl")
            pass_through = args.dup

            # Single adapter: just run it directly (in-process, no subprocess)
            if runs.adapters.size == 1
              adapter = runs.adapters.first
              extra = jsonl_mode ? pass_through + ["--jsonl"] : pass_through
              cmd = build_cmd(adapter.path, extra)
              exec_adapter(cmd)
              return
            end

            # Multiple adapters: run each sequentially, collect JSONL for comparison
            gem_root = File.expand_path("../../../../..", __FILE__)
            reports_dir = runs.reports_dir
            results_by_adapter = {}

            runs.adapters.each do |adapter|
              cmd = build_cmd(adapter.path, pass_through)
              run_id = Config.generate_run_id
              env = { "LIQUID_SPEC_RUN_ID" => run_id }

              if jsonl_mode
                # Suppress human output, just run for the files
                Dir.chdir(gem_root) { system(env, *cmd, out: File::NULL, err: File::NULL) }
              else
                Dir.chdir(gem_root) { system(env, *cmd) }
              end

              # Read back results from this run's jsonl
              jsonl_files = Dir[File.join(reports_dir, "#{adapter.name}.*.jsonl")].sort
              jsonl_path = jsonl_files.last
              if jsonl_path && File.exist?(jsonl_path)
                results_by_adapter[adapter.name] = File.readlines(jsonl_path).filter_map do |line|
                  data = JSON.parse(line, symbolize_names: true) rescue nil
                  if jsonl_mode && data
                    # Stream each line to stdout
                    puts JSON.generate(Benchmark.compact(data))
                    $stdout.flush
                  end
                  data if data && (data[:type] == "spec" || data[:type] == "result") && data[:status] == "success"
                end
              end
            end

            # Show cross-adapter comparison
            if results_by_adapter.size >= 2
              if jsonl_mode
                emit_comparison_jsonl(runs.adapter_names, results_by_adapter)
              else
                puts ""
                print_comparison(runs.adapter_names, results_by_adapter)
              end
            end
          end

          private

          def build_cmd(adapter_path, extra_args)
            cmd = ["bundle", "exec", "ruby"]
            # Pre-scan adapter for LiquidSpec.rubyopt declarations (e.g. "--yjit")
            rubyopt = scan_rubyopt(adapter_path)
            cmd += rubyopt if rubyopt.any?
            cmd += ["-Ilib", "bin/liquid-spec", "run", adapter_path,
                    "-s", "benchmarks", "--bench"]
            cmd += extra_args
            cmd
          end

          def exec_adapter(cmd)
            gem_root = File.expand_path("../../../../..", __FILE__)
            Dir.chdir(gem_root) { system(*cmd) }
          end

          # Scan an adapter file for LiquidSpec.rubyopt declarations
          # without executing it. Returns array of flags like ["--yjit"].
          def scan_rubyopt(adapter_path)
            return [] unless File.exist?(adapter_path)
            content = File.read(adapter_path)
            flags = []
            content.scan(/LiquidSpec\.rubyopt\s+["']([^"']+)["']/) do |match|
              flags.concat(match[0].split)
            end
            flags
          end

          def print_comparison(adapter_names, results_by_adapter)
            f = Benchmark.method(:fmt)
            reference = adapter_names.first
            others = adapter_names[1..]

            # Find common specs (handle both old :spec_name and new :spec keys)
            sk = ->(r) { r[:spec_name] || r[:spec] }
            all_specs = results_by_adapter.values.map { |rs| rs.map(&sk) }
            common = all_specs.reduce(:&) || []
            return if common.empty?

            puts "─" * 70
            puts "\e[1mComparison\e[0m (#{common.size} common specs, reference: #{reference})"
            puts ""

            parse_ratios = Hash.new { |h, k| h[k] = [] }
            render_ratios = Hash.new { |h, k| h[k] = [] }

            common.each do |sn|
              ref = results_by_adapter[reference]&.find { |r| sk.call(r) == sn }
              next unless ref

              ref_parse  = ref.dig(:parse, :mean) || ref[:parse_mean] || ref[:compile_mean]
              ref_render = ref.dig(:render, :mean) || ref[:render_mean]

              others.each do |other|
                o = results_by_adapter[other]&.find { |r| sk.call(r) == sn }
                next unless o

                o_parse  = o.dig(:parse, :mean) || o[:parse_mean] || o[:compile_mean]
                o_render = o.dig(:render, :mean) || o[:render_mean]

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

          def emit_comparison_jsonl(adapter_names, results_by_adapter)
            reference = adapter_names.first
            others = adapter_names[1..]

            all_specs = results_by_adapter.values.map { |rs| rs.map { |r| r[:spec_name] || r[:spec] } }
            common = all_specs.reduce(:&) || []
            return if common.empty?

            others.each do |other|
              parse_ratios = []
              render_ratios = []

              common.each do |spec_name|
                ref = results_by_adapter[reference]&.find { |r| (r[:spec_name] || r[:spec]) == spec_name }
                o = results_by_adapter[other]&.find { |r| (r[:spec_name] || r[:spec]) == spec_name }
                next unless ref && o

                rp = ref.dig(:parse, :mean) || ref[:parse_mean]
                op = o.dig(:parse, :mean) || o[:parse_mean]
                rr = ref.dig(:render, :mean) || ref[:render_mean]
                or_ = o.dig(:render, :mean) || o[:render_mean]

                parse_ratios << op / rp if rp && op && rp > 0
                render_ratios << or_ / rr if rr && or_ && rr > 0
              end

              entry = Benchmark.compact({
                type: "comparison",
                reference: reference,
                vs: other,
                common_specs: common.size,
                parse_geomean: geometric_mean(parse_ratios),
                render_geomean: geometric_mean(render_ratios),
                parse_faster: parse_ratios.any? ? (1.0 / geometric_mean(parse_ratios)) : nil,
                render_faster: render_ratios.any? ? (1.0 / geometric_mean(render_ratios)) : nil,
              })
              puts JSON.generate(entry)
              $stdout.flush
            end
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
