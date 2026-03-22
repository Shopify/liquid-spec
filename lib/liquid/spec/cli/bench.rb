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

            # Multiple adapters: run each with --jsonl to collect results,
            # then display interleaved per-spec comparison.
            gem_root = File.expand_path("../../../../..", __FILE__)
            reports_dir = runs.reports_dir
            results_by_adapter = {}
            adapter_names = runs.adapter_names
            pad = adapter_names.map(&:size).max

            f = Benchmark.method(:fmt)

            # ── Phase 1: Collect results from each adapter ───────────────
            unless jsonl_mode
              puts ""
              puts "\e[1mCollecting benchmarks\e[0m (#{adapter_names.size} adapters)"
              puts ""
            end

            runs.adapters.each do |adapter|
              cmd = build_cmd(adapter.path, pass_through + ["--jsonl"])
              run_id = Config.generate_run_id
              env = { "LIQUID_SPEC_RUN_ID" => run_id }

              unless jsonl_mode
                print "  \e[2m⏱\e[0m  #{adapter.name} …"
                $stdout.flush
              end

              # Run with JSONL to stdout, capture it
              output = Dir.chdir(gem_root) {
                IO.popen(env, cmd.map(&:to_s), err: File::NULL, &:read)
              }

              specs = []
              output.each_line do |line|
                data = JSON.parse(line.strip, symbolize_names: true) rescue nil
                next unless data
                if jsonl_mode
                  puts JSON.generate(Benchmark.compact(data))
                  $stdout.flush
                end
                specs << data if (data[:type] == "spec" || data[:type] == "result") && data[:status] == "success"
              end
              results_by_adapter[adapter.name] = specs

              unless jsonl_mode
                print "\r\e[2K"
                jit = specs.first&.dig(:jit) || "?"
                puts "  \e[32m✓\e[0m  #{adapter.name} (#{jit}, #{specs.size} specs)"
              end
            end

            # ── Phase 2: Interleaved per-spec display ────────────────────
            sk = ->(r) { r[:spec_name] || r[:spec] }
            all_spec_names = results_by_adapter.values.flatten.map(&sk).uniq

            unless jsonl_mode
              puts ""

              all_spec_names.each_with_index do |spec_name, idx|
                label = spec_name.sub(/\Abench_/, "")
                puts "\e[1mBenchmark #{idx + 1}/#{all_spec_names.size}:\e[0m #{label}"

                adapter_names.each do |name|
                  r = results_by_adapter[name]&.find { |x| sk.call(x) == spec_name }
                  unless r
                    puts "  \e[1m#{name.ljust(pad)}\e[0m  \e[2m(skipped)\e[0m"
                    next
                  end

                  # Extract values (handle both nested and flat formats)
                  pmean = r.dig(:parse, :mean) || r[:parse_mean] || 0
                  pstd  = r.dig(:parse, :stddev) || r[:parse_stddev] || 0
                  pall  = r.dig(:parse, :allocs) || r[:parse_allocs_per_op] || 0
                  pitr  = r.dig(:parse, :iters) || r[:parse_iters] || 0
                  rmean = r.dig(:render, :mean) || r[:render_mean] || 0
                  rstd  = r.dig(:render, :stddev) || r[:render_stddev] || 0
                  rmin  = r.dig(:render, :min) || r[:render_min] || 0
                  rmax  = r.dig(:render, :max) || r[:render_max] || 0
                  rall  = r.dig(:render, :allocs) || r[:render_allocs_per_op] || 0
                  ritr  = r.dig(:render, :iters) || r[:render_iters] || 0
                  cold1 = r.dig(:cold, :at_1) || r[:render_cold_1]
                  cold10 = r.dig(:cold, :at_10) || r[:render_cold_10_mean]

                  puts "  \e[1m#{name.ljust(pad)}\e[0m  " \
                       "Parse  (\e[1;32mmean\e[0m ± \e[32mσ\e[0m):  " \
                       "\e[1;32m#{f.call(pmean).rjust(9)}\e[0m ± " \
                       "\e[32m#{f.call(pstd).rjust(8)}\e[0m    " \
                       "[\e[34m#{Benchmark.fmt_allocs(pall)} allocs\e[0m, " \
                       "\e[2m#{Benchmark.fmt_iters(pitr)} runs\e[0m]"

                  puts "  #{" " * pad}  " \
                       "Render (\e[1;32mmean\e[0m ± \e[32mσ\e[0m):  " \
                       "\e[1;32m#{f.call(rmean).rjust(9)}\e[0m ± " \
                       "\e[32m#{f.call(rstd).rjust(8)}\e[0m    " \
                       "[\e[34m#{Benchmark.fmt_allocs(rall)} allocs\e[0m, " \
                       "\e[2m#{Benchmark.fmt_iters(ritr)} runs\e[0m]"

                  puts "  #{" " * pad}  " \
                       "Range  (\e[36mmin\e[0m … \e[35mmax\e[0m):  " \
                       "\e[36m#{f.call(rmin).rjust(9)}\e[0m … " \
                       "\e[35m#{f.call(rmax).rjust(8)}\e[0m    " \
                       "[\e[2m#{Benchmark.fmt_iters(ritr)} runs\e[0m]"

                  if cold1
                    ratio = rmean > 0 ? cold1 / rmean : 0
                    ratio_s = ratio > 1.05 ? "    \e[2m(%.1fx vs warm)\e[0m" % ratio : ""
                    puts "  #{" " * pad}  " \
                         "Cold   (\e[33m@1\e[0m / \e[33m@10\e[0m):  " \
                         "\e[33m#{f.call(cold1).rjust(9)}\e[0m / " \
                         "\e[33m#{f.call(cold10 || 0).rjust(8)}\e[0m" \
                         "#{ratio_s}"
                  end

                  # YJIT stats
                  yjit = r[:yjit]
                  if yjit && yjit[:iseqs]
                    parts = []
                    parts << "+#{yjit[:iseqs]} iseqs"
                    parts << "#{"%.1f" % yjit[:compile_ms]}ms jit" if yjit[:compile_ms] && yjit[:compile_ms] > 0.05
                    parts << "#{yjit[:invalidations]} inv"
                    parts << "#{"%.1f" % (yjit[:code_bytes] / 1024.0)}KB" if yjit[:code_bytes] && yjit[:code_bytes] > 0
                    puts "  #{" " * pad}  \e[2mYJIT:  #{parts.join("  │  ")}\e[0m"
                  end
                end

                # Per-spec speedup
                render_times = {}
                adapter_names.each do |a|
                  r = results_by_adapter[a]&.find { |x| sk.call(x) == spec_name }
                  render_times[a] = r.dig(:render, :mean) || r[:render_mean] if r
                end
                if render_times.size >= 2
                  fastest_name, fastest_t = render_times.min_by { |_, t| t }
                  slowest_name, slowest_t = render_times.max_by { |_, t| t }
                  if fastest_t > 0 && slowest_t / fastest_t > 1.1
                    puts "  \e[2m→ #{fastest_name} is %.2fx faster\e[0m" % (slowest_t / fastest_t)
                  end
                end

                puts ""
              end
            end

            # ── Phase 3: Overall comparison ──────────────────────────────
            if results_by_adapter.size >= 2
              if jsonl_mode
                emit_comparison_jsonl(adapter_names, results_by_adapter)
              else
                print_comparison(adapter_names, results_by_adapter)
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
