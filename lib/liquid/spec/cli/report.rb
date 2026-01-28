# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require_relative "config"

module Liquid
  module Spec
    module CLI
      # Report command - analyze and compare benchmark results across adapters
      module Report
        HELP = <<~HELP
          Usage: liquid-spec report [options]

          Analyze and compare benchmark results across adapters.
          Reads JSONL files from $LIQUID_SPEC_REPORTS (default: #{Config::DEFAULT_REPORTS_DIR}/)

          Results are grouped by: adapter, ruby_version, jit_engine
          Shows the latest run for each unique combination.

          Options:
            -o, --output=DIR      Reports directory (default: $LIQUID_SPEC_REPORTS or #{Config::DEFAULT_REPORTS_DIR})
            --adapter=NAME        Filter to specific adapter(s) (can be used multiple times)
            --spec=PATTERN        Filter specs by name pattern
            --summary             Show individual group summaries (default: comparison mode)
            --compare             Force comparison mode even with single group
            --trend               Show performance trends over time for each group
            --json                Output raw JSON data
            --detail              Show per-spec details
            -v, --verbose         Show more detail
            -h, --help            Show this help

          Examples:
            liquid-spec report
            liquid-spec report --compare
            liquid-spec report --adapter=liquid_ruby --compare
            liquid-spec report --spec=loops --trend
            liquid-spec report --json > results.json

        HELP

        class << self
          def run(args)
            if args.include?("-h") || args.include?("--help")
              puts HELP
              return
            end

            options = parse_options(args)

            reports_dir = Config.reports_dir(options[:output])

            unless Dir.exist?(reports_dir)
              puts "No benchmark data found at #{reports_dir}"
              puts "Run benchmarks first with: liquid-spec run adapter.rb -s benchmarks --bench"
              return
            end

            data = load_benchmark_data(reports_dir, options)

            if data.empty?
              puts "No benchmark data found"
              puts "Run benchmarks first with: liquid-spec run adapter.rb -s benchmarks --bench"
              return
            end

            if options[:json]
              output_json(data, options)
            elsif options[:trend]
              show_trends(data, options)
            elsif options[:summary]
              # Explicit summary mode
              show_summary(data, reports_dir, options)
            elsif data.size >= 2 || options[:compare]
              # Default to comparison when multiple groups exist
              show_comparison(data, reports_dir, options)
            else
              # Single group - show detailed summary
              show_summary(data, reports_dir, options)
            end
          end

          private

          def parse_options(args)
            options = {
              output: nil,
              adapters: [],
              spec_filter: nil,
              summary: false,
              compare: false,
              trend: false,
              json: false,
              detail: false,
              verbose: false,
            }

            while args.any?
              arg = args.shift
              case arg
              when /\A-o=?(.+)\z/
                options[:output] = ::Regexp.last_match(1)
              when "-o"
                options[:output] = args.shift
              when /\A--output=(.+)\z/
                options[:output] = ::Regexp.last_match(1)
              when "--output"
                options[:output] = args.shift
              when /\A--adapter=(.+)\z/
                options[:adapters] << ::Regexp.last_match(1)
              when "--adapter"
                options[:adapters] << args.shift
              when /\A--spec=(.+)\z/
                options[:spec_filter] = ::Regexp.last_match(1)
              when "--spec"
                options[:spec_filter] = args.shift
              when "--summary"
                options[:summary] = true
              when "--compare"
                options[:compare] = true
              when "--trend"
                options[:trend] = true
              when "--json"
                options[:json] = true
              when "--detail"
                options[:detail] = true
              when "-v", "--verbose"
                options[:verbose] = true
              end
            end

            options
          end

          def load_benchmark_data(reports_dir, options)
            # Load all JSONL files, group by (adapter, ruby_version, jit_engine)
            groups = Hash.new { |h, k| h[k] = { metadata: [], results: [] } }

            Dir[File.join(reports_dir, "*.jsonl")].each do |path|
              adapter_from_filename = File.basename(path, ".jsonl")
              next if options[:adapters].any? && !options[:adapters].include?(adapter_from_filename)

              File.foreach(path) do |line|
                next if line.strip.empty?

                begin
                  entry = JSON.parse(line, symbolize_names: true)

                  # Build group key from entry or infer from older format
                  group_key = entry[:group_key] || [
                    entry[:adapter] || entry[:adapter_name] || adapter_from_filename,
                    entry[:ruby_version] || "unknown",
                    entry[:jit_engine] || infer_jit_engine(entry[:jit]),
                  ]

                  # Filter by spec name if requested
                  if options[:spec_filter] && entry[:type] != "run_metadata"
                    pattern = parse_filter_pattern(options[:spec_filter])
                    spec_name = entry[:spec_name]
                    next if spec_name && !(spec_name =~ pattern)
                  end

                  group_key_str = group_key.join("|")

                  if entry[:type] == "run_metadata"
                    groups[group_key_str][:metadata] << entry
                  else
                    groups[group_key_str][:results] << entry
                  end
                rescue JSON::ParserError
                  # Skip malformed lines
                end
              end
            end

            # For each group, find the latest run
            groups.transform_values do |group_data|
              # Get all unique run_ids
              all_run_ids = (group_data[:metadata].map { |m| m[:run_id] } +
                            group_data[:results].map { |r| r[:run_id] }).compact.uniq.sort

              # Latest run
              latest_run_id = all_run_ids.max
              latest_metadata = group_data[:metadata].find { |m| m[:run_id] == latest_run_id }
              latest_results = group_data[:results].select { |r| r[:run_id] == latest_run_id }

              # Historical runs (for trends)
              historical = all_run_ids.map do |run_id|
                results = group_data[:results].select { |r| r[:run_id] == run_id }
                metadata = group_data[:metadata].find { |m| m[:run_id] == run_id }
                next if results.empty?

                {
                  run_id: run_id,
                  metadata: metadata,
                  results: results,
                }
              end.compact

              {
                metadata: latest_metadata,
                results: latest_results,
                historical: historical,
                all_run_ids: all_run_ids,
              }
            end
          end

          def infer_jit_engine(jit_status)
            case jit_status
            when "yjit" then "yjit"
            when "zjit" then "zjit"
            else "none"
            end
          end

          def parse_filter_pattern(pattern)
            if pattern =~ %r{\A/(.+)/([imx]*)\z}
              regex_str = ::Regexp.last_match(1)
              flags = ::Regexp.last_match(2)
              opts = 0
              opts |= Regexp::IGNORECASE if flags.include?("i")
              Regexp.new(regex_str, opts)
            else
              Regexp.new(pattern, Regexp::IGNORECASE)
            end
          end

          def output_json(data, _options)
            puts JSON.pretty_generate(data)
          end

          def show_summary(data, reports_dir, options)
            puts "=" * 70
            puts "BENCHMARK REPORT"
            puts "=" * 70
            puts "Data: #{reports_dir}/"
            puts ""

            data.each do |group_key_str, group_data|
              group_parts = group_key_str.split("|")
              adapter = group_parts[0]
              ruby_version = group_parts[1]
              jit_engine = group_parts[2]

              results = group_data[:results]
              metadata = group_data[:metadata]
              next if results.empty?

              successful = results.select { |r| r[:status] == "success" }
              failed = results.select { |r| r[:status] != "success" }

              # Calculate time since last run
              latest_timestamp = metadata&.dig(:started_at) || results.first&.dig(:timestamp)
              time_ago = latest_timestamp ? time_ago_in_words(latest_timestamp) : "unknown"

              jit_label = jit_engine == "none" ? "no-jit" : jit_engine

              puts "\e[1m#{adapter}\e[0m"
              puts "  Ruby #{ruby_version}, #{jit_label}"
              puts "  Last run: #{time_ago} (#{group_data[:all_run_ids].size} total runs)"
              puts ""

              total_count = successful.size + failed.size
              success_rate = total_count > 0 ? (successful.size.to_f / total_count * 100).round(1) : 0

              puts "  Tests: #{total_count} run, #{successful.size} passed, #{failed.size} failed (#{success_rate}% success)"

              if successful.any?
                # Use parse_ fields if available, fall back to compile_ for older data
                total_parse_ms = successful.sum { |r| ((r[:parse_mean] || r[:compile_mean]) || 0) * 1000 }
                total_render_ms = successful.sum { |r| (r[:render_mean] || 0) * 1000 }
                total_parse_allocs = successful.sum { |r| (r[:parse_allocs] || r[:compile_allocs]) || 0 }
                total_render_allocs = successful.sum { |r| r[:render_allocs] || 0 }
                total_parse_iters = successful.sum { |r| (r[:parse_iterations] || r[:compile_iterations]) || 0 }
                total_render_iters = successful.sum { |r| r[:render_iterations] || 0 }

                puts ""
                puts "  \e[1mParse:\e[0m  %12s total  %12s avg  (%s iterations)" % [
                  format_time(total_parse_ms),
                  format_time(total_parse_ms / successful.size),
                  format_number(total_parse_iters),
                ]
                puts "  \e[1mRender:\e[0m %12s total  %12s avg  (%s iterations)" % [
                  format_time(total_render_ms),
                  format_time(total_render_ms / successful.size),
                  format_number(total_render_iters),
                ]
                puts "  \e[1mAllocs:\e[0m %12s parse  %12s render" % [
                  format_number(total_parse_allocs),
                  format_number(total_render_allocs),
                ]
              end

              if options[:detail] && successful.any?
                puts ""
                puts "  \e[2mPer-Spec Results (sorted by render time):\e[0m"
                successful.sort_by { |r| -(r[:render_mean] || 0) }.each do |r|
                  parse_ms = ((r[:parse_mean] || r[:compile_mean]) || 0) * 1000
                  render_ms = (r[:render_mean] || 0) * 1000
                  puts "    #{r[:spec_name]}"
                  puts "      Parse:  #{format_time(parse_ms)}, Render: #{format_time(render_ms)}"
                end
              end

              puts ""
              puts "-" * 70
              puts ""
            end

            # Show comparison table if multiple successful groups
            successful_groups = data.select { |_, g| g[:results].any? { |r| r[:status] == "success" } }
            if successful_groups.size >= 2
              print_comparison_table(successful_groups)
            end
          end

          def print_comparison_table(groups)
            puts ""
            puts "=" * 70
            puts "COMPARISON TABLE"
            puts "=" * 70
            puts ""

            # Build table data
            rows = groups.map do |group_key, group_data|
              parts = group_key.split("|")
              successful = group_data[:results].select { |r| r[:status] == "success" }
              next nil if successful.empty?

              total_parse = successful.sum { |r| ((r[:parse_mean] || r[:compile_mean]) || 0) * 1000 }
              total_render = successful.sum { |r| (r[:render_mean] || 0) * 1000 }
              avg_parse = total_parse / successful.size
              avg_render = total_render / successful.size

              jit_label = parts[2] == "none" ? "no-jit" : parts[2]
              config = "#{parts[0]} (#{parts[1]}, #{jit_label})"

              {
                config: config,
                tests: successful.size,
                parse_avg: avg_parse,
                render_avg: avg_render,
              }
            end.compact

            return if rows.empty?

            # Find reference (first row)
            ref = rows.first

            # Calculate column widths
            max_config = [rows.map { |r| r[:config].length }.max, 13].max

            # Print header
            puts "\e[1m%-#{max_config}s  %6s  %12s  %12s  %12s  %12s\e[0m" % [
              "Configuration", "Tests", "Parse avg", "Render avg", "Parse Δ", "Render Δ"
            ]
            puts "-" * (max_config + 62)

            rows.each do |row|
              parse_delta = ref[:parse_avg] > 0 ? ((row[:parse_avg] / ref[:parse_avg] - 1) * 100).round(1) : 0
              render_delta = ref[:render_avg] > 0 ? ((row[:render_avg] / ref[:render_avg] - 1) * 100).round(1) : 0

              if row == ref
                parse_delta_str = "(ref)"
                render_delta_str = "(ref)"
              else
                parse_delta_str = "%+.1f%%" % parse_delta
                render_delta_str = "%+.1f%%" % render_delta

                # Color the deltas
                parse_delta_str = parse_delta < -5 ? "\e[32m#{parse_delta_str}\e[0m" : (parse_delta > 5 ? "\e[31m#{parse_delta_str}\e[0m" : parse_delta_str)
                render_delta_str = render_delta < -5 ? "\e[32m#{render_delta_str}\e[0m" : (render_delta > 5 ? "\e[31m#{render_delta_str}\e[0m" : render_delta_str)
              end

              # Right-align numbers, account for ANSI codes
              parse_delta_display = parse_delta_str.gsub(/\e\[[0-9;]*m/, "")
              render_delta_display = render_delta_str.gsub(/\e\[[0-9;]*m/, "")
              parse_delta_pad = 12 - parse_delta_display.length
              render_delta_pad = 12 - render_delta_display.length

              puts "%-#{max_config}s  %6d  %12s  %12s  %s%s  %s%s" % [
                row[:config],
                row[:tests],
                format_time(row[:parse_avg]),
                format_time(row[:render_avg]),
                " " * [parse_delta_pad, 0].max, parse_delta_str,
                " " * [render_delta_pad, 0].max, render_delta_str,
              ]
            end

            puts ""
          end

          def show_comparison(data, _reports_dir, options)
            if data.size < 2
              puts "Need at least 2 groups to compare"
              puts "Found: #{data.keys.join(", ")}"
              puts ""
              puts "Run benchmarks with different configurations:"
              puts "  - Different adapters: liquid-spec matrix --adapters=a,b --bench"
              puts "  - Different JIT: ruby --yjit bin/liquid-spec run ... --bench"
              return
            end

            puts "=" * 70
            puts "BENCHMARK COMPARISON"
            puts "=" * 70
            puts ""

            # Build comparison table
            group_keys = data.keys.sort

            # Find common specs across all groups
            all_spec_names = data.values.flat_map { |g| g[:results].map { |r| r[:spec_name] } }.uniq
            common_specs = all_spec_names.select do |spec_name|
              group_keys.all? do |gk|
                data[gk][:results].any? { |r| r[:spec_name] == spec_name && r[:status] == "success" }
              end
            end

            if common_specs.empty?
              puts "No specs found that ran successfully in all groups"
              return
            end

            puts "Comparing #{common_specs.size} common specs across #{group_keys.size} configurations"
            puts ""

            # Print group headers with test counts
            puts "Groups:"
            group_keys.each_with_index do |gk, idx|
              parts = gk.split("|")
              jit_label = parts[2] == "none" ? "no-jit" : parts[2]
              time_ago = time_ago_in_words(data[gk][:metadata]&.dig(:started_at) || data[gk][:results].first&.dig(:timestamp))
              results = data[gk][:results]
              total = results.size
              passed = results.count { |r| r[:status] == "success" }
              rate = total > 0 ? (passed.to_f / total * 100).round(0) : 0
              puts "  #{idx + 1}. #{parts[0]} (Ruby #{parts[1]}, #{jit_label}) - #{passed}/#{total} passed (#{rate}%) - #{time_ago}"
            end
            puts ""

            # Reference is first group
            reference_key = group_keys.first
            other_keys = group_keys[1..]

            parse_ratios = Hash.new { |h, k| h[k] = [] }
            render_ratios = Hash.new { |h, k| h[k] = [] }

            common_specs.each do |spec_name|
              ref_result = data[reference_key][:results].find { |r| r[:spec_name] == spec_name && r[:status] == "success" }
              next unless ref_result

              ref_parse = ref_result[:parse_mean] || ref_result[:compile_mean]
              ref_render = ref_result[:render_mean]

              other_keys.each do |other_key|
                other_result = data[other_key][:results].find { |r| r[:spec_name] == spec_name && r[:status] == "success" }
                next unless other_result

                other_parse = other_result[:parse_mean] || other_result[:compile_mean]
                other_render = other_result[:render_mean]

                parse_ratios[other_key] << other_parse / ref_parse if ref_parse && other_parse && ref_parse > 0
                render_ratios[other_key] << other_render / ref_render if ref_render && other_render && ref_render > 0
              end
            end

            puts "-" * 70
            puts "RESULTS (reference: group 1)"
            puts "-" * 70
            puts ""

            ref_parts = reference_key.split("|")
            ref_label = "#{ref_parts[0]} (#{ref_parts[1]}, #{ref_parts[2] == "none" ? "no-jit" : ref_parts[2]})"

            # Build comparison table data
            comparison_rows = []
            group_keys.each_with_index do |key, idx|
              parts = key.split("|")
              label = "#{parts[0]} (#{parts[1]}, #{parts[2] == "none" ? "no-jit" : parts[2]})"

              results = data[key][:results].select { |r| r[:status] == "success" && common_specs.include?(r[:spec_name]) }
              total_parse_allocs = results.sum { |r| (r[:parse_allocs] || r[:compile_allocs]) || 0 }
              total_render_allocs = results.sum { |r| r[:render_allocs] || 0 }

              parse_geomean = idx == 0 ? 1.0 : geometric_mean(parse_ratios[key])
              render_geomean = idx == 0 ? 1.0 : geometric_mean(render_ratios[key])

              comparison_rows << {
                label: label,
                parse_ratio: parse_geomean,
                render_ratio: render_geomean,
                parse_allocs: total_parse_allocs,
                render_allocs: total_render_allocs,
                is_ref: idx == 0,
              }
            end

            # Find max label width
            max_label = comparison_rows.map { |r| r[:label].length }.max

            # Print comparison table
            puts "\e[1m%-#{max_label}s  %12s  %12s  %14s  %14s\e[0m" % ["Configuration", "Parse", "Render", "Parse Allocs", "Render Allocs"]
            puts "-" * (max_label + 58)

            comparison_rows.each do |row|
              if row[:is_ref]
                parse_str = "(ref)"
                render_str = "(ref)"
              else
                # Parse comparison
                if row[:parse_ratio] > 1.05
                  parse_str = "\e[31m%.2fx slower\e[0m" % row[:parse_ratio]
                elsif row[:parse_ratio] < 0.95
                  parse_str = "\e[32m%.2fx faster\e[0m" % (1.0 / row[:parse_ratio])
                else
                  parse_str = "~same"
                end

                # Render comparison
                if row[:render_ratio] > 1.05
                  render_str = "\e[31m%.2fx slower\e[0m" % row[:render_ratio]
                elsif row[:render_ratio] < 0.95
                  render_str = "\e[32m%.2fx faster\e[0m" % (1.0 / row[:render_ratio])
                else
                  render_str = "~same"
                end
              end

              # Right-align numbers, account for ANSI codes
              parse_display = parse_str.gsub(/\e\[[0-9;]*m/, "")
              render_display = render_str.gsub(/\e\[[0-9;]*m/, "")
              parse_pad = 12 - parse_display.length
              render_pad = 12 - render_display.length

              puts "%-#{max_label}s  %s%s  %s%s  %14s  %14s" % [
                row[:label],
                " " * [parse_pad, 0].max, parse_str,
                " " * [render_pad, 0].max, render_str,
                format_number(row[:parse_allocs]),
                format_number(row[:render_allocs]),
              ]
            end

            puts ""

            # Detail view
            if options[:detail]
              puts "-" * 70
              puts "PER-SPEC COMPARISON"
              puts "-" * 70
              puts ""

              common_specs.each do |spec_name|
                puts "\e[1m#{spec_name}\e[0m"

                results = group_keys.map do |key|
                  r = data[key][:results].find { |res| res[:spec_name] == spec_name && res[:status] == "success" }
                  [key, r] if r
                end.compact.to_h

                # Parse comparison
                parse_sorted = results.sort_by { |_, r| r[:parse_mean] || r[:compile_mean] || Float::INFINITY }
                fastest_key, fastest = parse_sorted.first

                puts "  Parse:"
                parse_sorted.each do |key, r|
                  parts = key.split("|")
                  label = "#{parts[0]} (#{parts[1]}, #{parts[2] == "none" ? "no-jit" : parts[2]})"
                  parse_time = (r[:parse_mean] || r[:compile_mean]) * 1000
                  fastest_time = (fastest[:parse_mean] || fastest[:compile_mean]) * 1000
                  if key == fastest_key
                    puts "    \e[32m#{label}\e[0m: #{format_time(parse_time)}"
                  else
                    ratio = parse_time / fastest_time
                    puts "    #{label}: #{format_time(parse_time)} (%.2fx)" % ratio
                  end
                end

                # Render comparison
                render_sorted = results.sort_by { |_, r| r[:render_mean] || Float::INFINITY }
                fastest_key, fastest = render_sorted.first

                puts "  Render:"
                render_sorted.each do |key, r|
                  parts = key.split("|")
                  label = "#{parts[0]} (#{parts[1]}, #{parts[2] == "none" ? "no-jit" : parts[2]})"
                  render_time = r[:render_mean] * 1000
                  fastest_time = fastest[:render_mean] * 1000
                  if key == fastest_key
                    puts "    \e[32m#{label}\e[0m: #{format_time(render_time)}"
                  else
                    ratio = render_time / fastest_time
                    puts "    #{label}: #{format_time(render_time)} (%.2fx)" % ratio
                  end
                end

                puts ""
              end
            end
          end

          def show_trends(data, options)
            puts "=" * 70
            puts "PERFORMANCE TRENDS"
            puts "=" * 70
            puts ""

            data.each do |group_key_str, group_data|
              group_parts = group_key_str.split("|")
              adapter = group_parts[0]
              ruby_version = group_parts[1]
              jit_engine = group_parts[2]
              jit_label = jit_engine == "none" ? "no-jit" : jit_engine

              historical = group_data[:historical]

              puts "\e[1m#{adapter}\e[0m (Ruby #{ruby_version}, #{jit_label})"
              puts ""

              if historical.size < 2
                puts "  Only 1 run found, need multiple runs to show trends"
                puts ""
                next
              end

              puts "  \e[2m#{historical.size} runs:\e[0m"
              puts ""

              # Show last 10 runs with trends
              historical.last(10).each_with_index do |run, idx|
                prev_run = idx > 0 ? historical[idx - 1] : nil

                successful = run[:results].select { |r| r[:status] == "success" }
                next if successful.empty?

                avg_parse = successful.sum { |r| (r[:parse_mean] || r[:compile_mean]) || 0 } / successful.size
                avg_render = successful.sum { |r| r[:render_mean] || 0 } / successful.size
                total_allocs = successful.sum { |r| ((r[:parse_allocs] || r[:compile_allocs]) || 0) + (r[:render_allocs] || 0) }

                time_ago = time_ago_in_words(run[:metadata]&.dig(:started_at) || run[:results].first&.dig(:timestamp))
                total = run[:results].size
                failed = total - successful.size
                rate = total > 0 ? (successful.size.to_f / total * 100).round(0) : 0

                puts "  #{run[:run_id]} (#{time_ago})"
                puts "    Tests: #{total} run, #{successful.size} passed, #{failed} failed (#{rate}%)"

                # Parse trend
                parse_ms = avg_parse * 1000
                parse_str = "    Parse:  #{format_time(parse_ms)}"
                if prev_run
                  prev_successful = prev_run[:results].select { |r| r[:status] == "success" }
                  if prev_successful.any?
                    prev_parse = prev_successful.sum { |r| (r[:parse_mean] || r[:compile_mean]) || 0 } / prev_successful.size * 1000
                    diff_pct = ((parse_ms - prev_parse) / prev_parse * 100).round(1)
                    if diff_pct.abs > 1
                      color = diff_pct < 0 ? "\e[32m" : "\e[31m"
                      parse_str += " #{color}(%+.1f%%)\e[0m" % diff_pct
                    end
                  end
                end
                puts parse_str

                # Render trend
                render_ms = avg_render * 1000
                render_str = "    Render: #{format_time(render_ms)}"
                if prev_run
                  prev_successful = prev_run[:results].select { |r| r[:status] == "success" }
                  if prev_successful.any?
                    prev_render = prev_successful.sum { |r| r[:render_mean] || 0 } / prev_successful.size * 1000
                    diff_pct = ((render_ms - prev_render) / prev_render * 100).round(1)
                    if diff_pct.abs > 1
                      color = diff_pct < 0 ? "\e[32m" : "\e[31m"
                      render_str += " #{color}(%+.1f%%)\e[0m" % diff_pct
                    end
                  end
                end
                puts render_str

                # Allocations trend
                allocs_str = "    Allocs: #{format_number(total_allocs)}"
                if prev_run
                  prev_successful = prev_run[:results].select { |r| r[:status] == "success" }
                  if prev_successful.any?
                    prev_allocs = prev_successful.sum { |r| ((r[:parse_allocs] || r[:compile_allocs]) || 0) + (r[:render_allocs] || 0) }
                    diff = total_allocs - prev_allocs
                    if diff != 0
                      color = diff < 0 ? "\e[32m" : "\e[31m"
                      allocs_str += " #{color}(%+d)\e[0m" % diff
                    end
                  end
                end
                puts allocs_str

                puts ""
              end

              # Overall trend summary
              if historical.size >= 2
                first = historical.first
                last = historical.last

                first_successful = first[:results].select { |r| r[:status] == "success" }
                last_successful = last[:results].select { |r| r[:status] == "success" }

                if first_successful.any? && last_successful.any?
                  first_parse = first_successful.sum { |r| (r[:parse_mean] || r[:compile_mean]) || 0 } / first_successful.size
                  last_parse = last_successful.sum { |r| (r[:parse_mean] || r[:compile_mean]) || 0 } / last_successful.size
                  first_render = first_successful.sum { |r| r[:render_mean] || 0 } / first_successful.size
                  last_render = last_successful.sum { |r| r[:render_mean] || 0 } / last_successful.size

                  parse_change = ((last_parse - first_parse) / first_parse * 100).round(1)
                  render_change = ((last_render - first_render) / first_render * 100).round(1)

                  puts "  \e[1mOverall Change (#{first[:run_id]} → #{last[:run_id]}):\e[0m"
                  parse_color = parse_change < 0 ? "\e[32m" : "\e[31m"
                  render_color = render_change < 0 ? "\e[32m" : "\e[31m"
                  puts "    Parse:  #{parse_color}%+.1f%%\e[0m" % parse_change
                  puts "    Render: #{render_color}%+.1f%%\e[0m" % render_change
                  puts ""
                end
              end

              puts "-" * 70
              puts ""
            end
          end

          def time_ago_in_words(timestamp)
            return "unknown" unless timestamp

            begin
              time = Time.parse(timestamp.to_s)
              diff = Time.now - time

              if diff < 60
                "just now"
              elsif diff < 3600
                "#{(diff / 60).to_i} minutes ago"
              elsif diff < 86400
                "#{(diff / 3600).to_i} hours ago"
              elsif diff < 604800
                "#{(diff / 86400).to_i} days ago"
              else
                "#{(diff / 604800).to_i} weeks ago"
              end
            rescue
              "unknown"
            end
          end

          def geometric_mean(arr)
            return 0 if arr.empty?
            (arr.reduce(1.0) { |prod, x| prod * x })**(1.0 / arr.size)
          end

          def format_time(ms)
            if ms >= 1000
              "%.3f s" % (ms / 1000.0)
            elsif ms >= 1
              "%.3f ms" % ms
            else
              "%.3f µs" % (ms * 1000)
            end
          end

          def format_number(num)
            return "0" if num.nil? || num.zero?
            num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
          end
        end
      end
    end
  end
end
