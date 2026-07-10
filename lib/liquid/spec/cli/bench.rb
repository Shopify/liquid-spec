# frozen_string_literal: true

require "rbconfig"
require_relative "benchmark"
require_relative "config"
require_relative "runs"

module Liquid
  module Spec
    module CLI
      # `liquid-spec bench` — run benchmarks sequentially with nice per-spec output.
      #
      # - `liquid-spec bench`              → default builtin adapters, one after another
      # - `liquid-spec bench my_adapter.rb` → my_adapter vs liquid_ruby
      # - `liquid-spec bench my_adapter.rb -n storefront` → filtered
      #
      # Each adapter runs as a subprocess with full hyperfine-style output.
      # If multiple adapters, a comparison summary is shown at the end.
      module Bench
        HELP = <<~HELP
          Usage: liquid-spec bench [ADAPTER] [options]

          Run benchmarks with hyperfine-style output.

          With no adapter:    runs default builtin adapters sequentially
          With an adapter:    runs ADAPTER vs liquid_ruby (reference)

          Comparisons that mix inline and JSON-RPC adapters emit a warning because
          JSON-RPC timings include subprocess and protocol overhead.

          Options:
            -n, --name PATTERN    Filter specs by name pattern
            -s, --suite SUITE     Spec suite (default: benchmarks)
            --all                 Run all default builtin adapters
            --adapter=PATH        Add a specific adapter
            --adapters=LIST       Comma-separated adapter list
            --profile             Write StackProf CPU/allocation profiles to /tmp
            --jsonl               Stream machine-readable benchmark events
            -v, --verbose         Verbose output
            -h, --help            Show this help

          Examples:
            liquid-spec bench
            liquid-spec bench my_adapter.rb
            liquid-spec bench my_adapter.rb -n storefront
            liquid-spec bench --adapters=liquid_ruby,liquid_ruby_lax
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
            warn_mixed_transport_comparison(runs) if runs.adapters.size > 1

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
            metadata_by_adapter = {}
            profile_dirs = []
            profile_requested = pass_through.include?("--profile")
            adapter_names = runs.adapter_names
            pad = adapter_names.map(&:size).max

            # ── Phase 1: Collect results from each adapter ───────────────
            unless jsonl_mode
              puts ""
              puts "\e[1;36m◆ LIQUID BENCH · GRID\e[0m"
              puts "\e[2m  #{adapter_names.size} engines  ·  collecting benchmark runs  ·  lower is better\e[0m"
              puts ""
            end

            invoked_from = Dir.pwd
            runs.adapters.each do |adapter|
              cmd = build_cmd(adapter.path, pass_through + ["--jsonl"])
              run_id = Config.generate_run_id
              env = {
                "LIQUID_SPEC_RUN_ID" => run_id,
                "LIQUID_SPEC_LOCAL_DIR" => invoked_from,
                "LIQUID_SPEC_INTERNAL_BENCH" => "1",
              }
              if profile_requested
                safe_adapter_name = adapter.name.gsub(/[^a-zA-Z0-9_.-]/, "_")
                profile_dir = "/tmp/liquid-spec-profile-#{run_id}-#{safe_adapter_name}"
                env["LIQUID_SPEC_PROFILE_DIR"] = profile_dir
              end

              unless jsonl_mode
                print "  \e[36m◐\e[0m  #{adapter.name.ljust(pad)}  \e[2mwarming → sampling\e[0m"
                $stdout.flush
              end

              # Run with JSONL to stdout, capture it
              output, process_status = Dir.chdir(gem_root) do
                captured = IO.popen(env, cmd.map(&:to_s), err: File::NULL, &:read)
                [captured, $?]
              end

              specs = []
              metadata = nil
              output.each_line do |line|
                data = JSON.parse(line.strip, symbolize_names: true) rescue nil
                next unless data
                if jsonl_mode
                  puts JSON.generate(Benchmark.compact(data))
                  $stdout.flush
                end
                metadata = data if data[:type] == "run_metadata"
                specs << data if (data[:type] == "spec" || data[:type] == "result") && data[:status] == "success"
              end
              begin
                validate_adapter_subprocess!(adapter.name, process_status, metadata)
              rescue RuntimeError => error
                print "\r\e[2K" unless jsonl_mode
                warn "Error: #{error.message}"
                exit(1)
              end

              results_by_adapter[adapter.name] = specs
              metadata_by_adapter[adapter.name] = metadata
              profile_dirs << [adapter.name, profile_dir] if profile_dir && Dir.exist?(profile_dir)

              unless jsonl_mode
                print "\r\e[2K"
                jit = specs.first&.dig(:jit) || "?"
                case_label = specs.size == 1 ? "case" : "cases"
                puts "  \e[32m✓\e[0m  #{adapter.name.ljust(pad)}  \e[2m#{jit} · #{specs.size} #{case_label}\e[0m"
              end
            end

            unless jsonl_mode
              missing_artifacts = adapter_names.select do |name|
                metadata_by_adapter[name]&.dig(:artifact_protocol) == false
              end
              if missing_artifacts.any?
                puts ""
                puts "  \e[33m◇ artifact lane unavailable\e[0m  \e[2m#{missing_artifacts.join(", ")} · no compiled-artifact hooks\e[0m"
              end
            end

            if profile_dirs.any? && !jsonl_mode
              puts ""
              puts "\e[1mStackProf profiles\e[0m"
              profile_dirs.each { |name, dir| puts "  #{name}: #{dir}/" }
            end

            # ── Phase 2: Interleaved per-spec display ────────────────────
            sk = ->(r) { r[:spec_name] || r[:spec] }
            all_spec_names = results_by_adapter.values.flatten.map(&sk).uniq

            unless jsonl_mode
              puts ""

              all_spec_names.each_with_index do |spec_name, idx|
                print_case_comparison(
                  spec_name, idx + 1, all_spec_names.size,
                  adapter_names, results_by_adapter, sk, pad,
                )
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

          def warn_mixed_transport_comparison(runs)
            return unless runs.mixed_transports?

            groups = runs.adapters_by_transport
            inline = groups.fetch(:inline, []).map(&:name).join(", ")
            json_rpc = groups.fetch(:json_rpc, []).map(&:name).join(", ")
            warn <<~WARNING

              WARNING: This benchmark compares inline and JSON-RPC adapters.
              JSON-RPC measurements include subprocess and protocol overhead, so the
              performance results are not directly comparable.
                Inline:   #{inline}
                JSON-RPC: #{json_rpc}
            WARNING
          end

          private

          def print_case_comparison(spec_name, index, total, adapter_names, results_by_adapter, spec_key, pad)
            label = spec_name.sub(/\Abench_/, "")
            rows = adapter_names.to_h do |name|
              result = results_by_adapter[name]&.find { |entry| spec_key.call(entry) == spec_name }
              [name, result]
            end

            source_values = rows.values.filter_map { |r| r&.dig(:workflows, :source_compile_render, :mean) }
            artifact_values = rows.values.filter_map { |r| r&.dig(:workflows, :artifact_load_first_render, :mean) }
            resident_values = rows.values.filter_map { |r| r&.dig(:render, :mean) || r&.[](:render_mean) }
            fastest = {
              source: source_values.min,
              artifact: artifact_values.min,
              resident: resident_values.min,
            }

            puts "\e[2m#{"━" * 78}\e[0m"
            puts "\e[1;36m◆\e[0m  \e[1m#{label}\e[0m  \e[2m#{index}/#{total}\e[0m"
            puts ""
            puts "  #{"adapter".ljust(pad)}  #{"source → 1st".rjust(13)}  #{"artifact → 1st".rjust(14)}  #{"resident".rjust(11)}  #{"payload".rjust(10)}"
            puts "  \e[2m#{"─" * pad}  #{"─" * 13}  #{"─" * 14}  #{"─" * 11}  #{"─" * 10}\e[0m"

            rows.each do |name, result|
              unless result
                puts "  #{name.ljust(pad)}  \e[2m#{"skipped".rjust(54)}\e[0m"
                next
              end

              source = result.dig(:workflows, :source_compile_render, :mean)
              artifact = result.dig(:workflows, :artifact_load_first_render, :mean)
              resident = result.dig(:render, :mean) || result[:render_mean]
              bytes = result.dig(:artifact, :bytes) || result[:artifact_bytes]

              puts "  \e[1m#{name.ljust(pad)}\e[0m  " \
                   "#{comparison_value(source, fastest[:source], 33, 13)}  " \
                   "#{comparison_value(artifact, fastest[:artifact], 35, 14)}  " \
                   "#{comparison_value(resident, fastest[:resident], 36, 11)}  " \
                   "#{Benchmark.fmt_bytes(bytes).rjust(10)}"

              parse = result.dig(:parse, :mean) || result[:parse_mean]
              load = result.dig(:artifact, :load_mean) || result[:load_mean]
              stddev = result.dig(:render, :stddev) || result[:render_stddev]
              stability, cv = Benchmark.stability(resident, stddev)
              diagnostics = ["parse #{Benchmark.fmt_metric(parse)}"]
              diagnostics << "load #{Benchmark.fmt_metric(load)}" if load
              diagnostics << "#{stability} #{"%.1f" % (cv * 100)}% CV" if cv.positive?
              puts "  #{" " * pad}  \e[2m#{diagnostics.join("  ·  ")}\e[0m"
            end

            print_case_winner("source lane", rows, fastest[:source]) { |r| r.dig(:workflows, :source_compile_render, :mean) }
            print_case_winner("artifact lane", rows, fastest[:artifact]) { |r| r.dig(:workflows, :artifact_load_first_render, :mean) }
            print_case_winner("resident lane", rows, fastest[:resident]) { |r| r.dig(:render, :mean) || r[:render_mean] }
            puts ""
          end

          def comparison_value(value, fastest, color, width)
            return "—".rjust(width) unless value
            formatted = Benchmark.fmt_metric(value).rjust(width)
            value == fastest ? "\e[1;#{color}m#{formatted}\e[0m" : formatted
          end

          def print_case_winner(label, rows, fastest)
            return unless fastest
            ranked = rows.filter_map do |name, result|
              value = yield(result) if result
              [name, value] if value
            end.sort_by(&:last)
            return if ranked.size < 2

            winner, best = ranked[0]
            runner_up, second = ranked[1]
            ratio = second / best
            return if ratio < 1.03

            puts "  \e[2m↳ #{label}: \e[1m#{winner}\e[22m leads #{runner_up} by #{"%.2f" % ratio}×\e[0m"
          end

          def build_cmd(adapter_path, extra_args)
            # Reuse the current Ruby process rather than resolving the gem's own
            # development Gemfile. If liquid-spec was launched through Bundler,
            # its environment is inherited and still selects the caller's bundle.
            cmd = [RbConfig.ruby]
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
            env = {
              "LIQUID_SPEC_LOCAL_DIR" => Dir.pwd,
              "LIQUID_SPEC_INTERNAL_BENCH" => "1",
            }
            success = Dir.chdir(gem_root) { system(env, *cmd) }
            return if success

            status = $?
            warn "Error: benchmark adapter exited with #{status&.exitstatus || status.inspect}"
            exit(1)
          end

          def validate_adapter_subprocess!(adapter_name, status, metadata)
            unless status&.success?
              outcome = if status&.signaled?
                "signal #{status.termsig}"
              else
                "status #{status&.exitstatus || "unknown"}"
              end
              raise "benchmark adapter #{adapter_name} exited with #{outcome}"
            end
            return if metadata

            raise "benchmark adapter #{adapter_name} produced no run metadata"
          end

          # Scan an adapter file for LiquidSpec.rubyopt declarations
          # without executing it. Returns array of flags like ["--yjit"].
          def scan_rubyopt(adapter_path)
            return [] unless File.exist?(adapter_path)
            content = File.read(adapter_path, encoding: Encoding::UTF_8)
            flags = []
            content.scan(/LiquidSpec\.rubyopt\s+["']([^"']+)["']/) do |match|
              flags.concat(match[0].split)
            end
            flags
          end

          def print_comparison(adapter_names, results_by_adapter)
            reference = adapter_names.first
            others = adapter_names[1..]

            # Find common specs (handle both old :spec_name and new :spec keys)
            sk = ->(r) { r[:spec_name] || r[:spec] }
            all_specs = results_by_adapter.values.map { |rs| rs.map(&sk) }
            common = all_specs.reduce(:&) || []
            return if common.empty?

            puts "\e[2m#{"━" * 78}\e[0m"
            case_label = common.size == 1 ? "case" : "cases"
            puts "\e[1;36m◆ FINISH LINE\e[0m  \e[1mgeometric mean across #{common.size} common #{case_label}\e[0m"
            puts "\e[2m  ratios are paired against #{reference}  ·  lower time wins\e[0m"
            puts ""

            source_workflow_ratios = Hash.new { |h, k| h[k] = [] }
            artifact_workflow_ratios = Hash.new { |h, k| h[k] = [] }
            parse_ratios = Hash.new { |h, k| h[k] = [] }
            render_ratios = Hash.new { |h, k| h[k] = [] }
            load_ratios = Hash.new { |h, k| h[k] = [] }

            common.each do |sn|
              ref = results_by_adapter[reference]&.find { |r| sk.call(r) == sn }
              next unless ref

              ref_source = ref.dig(:workflows, :source_compile_render, :mean)
              ref_artifact = ref.dig(:workflows, :artifact_load_first_render, :mean)
              ref_parse  = ref.dig(:parse, :mean) || ref[:parse_mean] || ref[:compile_mean]
              ref_render = ref.dig(:render, :mean) || ref[:render_mean]
              ref_load   = ref.dig(:artifact, :load_mean) || ref[:load_mean]

              others.each do |other|
                o = results_by_adapter[other]&.find { |r| sk.call(r) == sn }
                next unless o

                o_source = o.dig(:workflows, :source_compile_render, :mean)
                o_artifact = o.dig(:workflows, :artifact_load_first_render, :mean)
                o_parse  = o.dig(:parse, :mean) || o[:parse_mean] || o[:compile_mean]
                o_render = o.dig(:render, :mean) || o[:render_mean]
                o_load   = o.dig(:artifact, :load_mean) || o[:load_mean]

                source_workflow_ratios[other] << o_source / ref_source if ref_source && o_source && ref_source > 0
                artifact_workflow_ratios[other] << o_artifact / ref_artifact if ref_artifact && o_artifact && ref_artifact > 0
                parse_ratios[other]  << o_parse / ref_parse   if ref_parse  && o_parse  && ref_parse  > 0
                render_ratios[other] << o_render / ref_render if ref_render && o_render && ref_render > 0
                load_ratios[other]   << o_load / ref_load     if ref_load   && o_load   && ref_load   > 0
              end
            end

            print_ratio_comparison("Source compile + first render", reference, others, source_workflow_ratios)
            if artifact_workflow_ratios.any? { |_, values| values.any? }
              print_ratio_comparison("Artifact load + first render", reference, others, artifact_workflow_ratios)
            end

            print_ratio_comparison("Resident render", reference, others, render_ratios)

            puts "  \e[2mSTAGE DIAGNOSTICS\e[0m"
            print_ratio_rows("parse", reference, others, parse_ratios, dim: true)
            print_ratio_rows("artifact load", reference, others, load_ratios, dim: true) if load_ratios.any? { |_, v| v.any? }

            puts ""
          end

          def print_ratio_comparison(label, reference, others, ratios_by_adapter)
            return unless others.any? { |adapter| ratios_by_adapter[adapter].any? }

            puts "  \e[1m#{label}\e[0m"
            print_ratio_rows(nil, reference, others, ratios_by_adapter)
            puts ""
          end

          def print_ratio_rows(prefix, reference, others, ratios_by_adapter, dim: false)
            others.each do |adapter|
              ratios = ratios_by_adapter[adapter]
              next if ratios.empty?

              ratio = geometric_mean(ratios)
              winner, loser, speedup = if ratio > 1.0
                [reference, adapter, ratio]
              else
                [adapter, reference, 1.0 / ratio]
              end
              bar_length = [[((speedup - 1.0) * 10).round + 3, 3].max, 18].min
              bar = "█" * bar_length
              verdict = speedup < 1.03 ? "photo finish" : "#{winner} · #{"%.2f" % speedup}× faster"
              line = "    #{prefix ? "#{prefix}: " : ""}#{adapter.ljust(20)} #{bar.ljust(18)}  #{verdict}"
              puts(dim ? "\e[2m#{line}\e[0m" : "\e[36m#{line}\e[0m")
            end
          end

          def emit_comparison_jsonl(adapter_names, results_by_adapter)
            reference = adapter_names.first
            others = adapter_names[1..]

            all_specs = results_by_adapter.values.map { |rs| rs.map { |r| r[:spec_name] || r[:spec] } }
            common = all_specs.reduce(:&) || []
            return if common.empty?

            others.each do |other|
              source_ratios = []
              artifact_ratios = []
              parse_ratios = []
              render_ratios = []

              common.each do |spec_name|
                ref = results_by_adapter[reference]&.find { |r| (r[:spec_name] || r[:spec]) == spec_name }
                o = results_by_adapter[other]&.find { |r| (r[:spec_name] || r[:spec]) == spec_name }
                next unless ref && o

                rs = ref.dig(:workflows, :source_compile_render, :mean)
                os = o.dig(:workflows, :source_compile_render, :mean)
                ra = ref.dig(:workflows, :artifact_load_first_render, :mean)
                oa = o.dig(:workflows, :artifact_load_first_render, :mean)
                rp = ref.dig(:parse, :mean) || ref[:parse_mean]
                op = o.dig(:parse, :mean) || o[:parse_mean]
                rr = ref.dig(:render, :mean) || ref[:render_mean]
                or_ = o.dig(:render, :mean) || o[:render_mean]

                source_ratios << os / rs if rs && os && rs > 0
                artifact_ratios << oa / ra if ra && oa && ra > 0
                parse_ratios << op / rp if rp && op && rp > 0
                render_ratios << or_ / rr if rr && or_ && rr > 0
              end

              entry = Benchmark.compact({
                type: "comparison",
                reference: reference,
                vs: other,
                common_specs: common.size,
                source_compile_render_geomean: geometric_mean(source_ratios),
                artifact_load_first_render_geomean: geometric_mean(artifact_ratios),
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
