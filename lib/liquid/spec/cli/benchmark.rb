# frozen_string_literal: true

module Liquid
  module Spec
    module CLI
      # Shared benchmark infrastructure.
      #
      # Methodology:
      #   1. Cold renders: measure first render (no JIT, cold caches) and
      #      mean of first 10 renders before any warmup.
      #   2. Warmup: run compile+render in a loop for ≥1s / ≥50 iters to
      #      let JIT (YJIT/ZJIT) stabilize and caches fill.
      #   3. Stabilize: full GC + compact to settle the heap.
      #   4. Allocation count: median of 3 isolated runs (GC between each).
      #   5. Timed phase: use the engine's normal GC policy and clock batches
      #      of operations to minimize timer overhead. Environment copies are
      #      prepared outside the timer.
      #   6. Preserve raw integer-nanosecond batches for downstream analysis.
      #
      # Summary times remain in seconds for compatibility with existing
      # reports. Raw batch measurements use integer nanoseconds.
      module Benchmark
        WARMUP_SECONDS        = 1.0
        WARMUP_MIN_ITERS      = 50
        TARGET_BATCH_SECS     = 0.02
        MAX_BATCH_SIZE        = 2_000
        MAX_ITERS             = 500_000

        class << self
          # Run a full benchmark for one spec.
          #
          # @param compile_proc [Proc]   -> { compile the template }
          # @param render_proc  [Proc]   ->(env) { render with env }
          # @param env_proc     [Proc]   -> { fresh env shallow-dup }
          # @param duration     [Float]  total seconds (split compile/render)
          # @param dump_proc    [Proc, nil] -> { serialize compiled template → String }
          # @param load_proc    [Proc, nil] ->(blob) { load artifact → renderable template }
          # @return [Hash] result with all metrics, or { error: Exception }
          #
          # When dump_proc AND load_proc are given, this same-process diagnostic
          # stage reports payload bytes, first load/render observations, and
          # steady-state load time/allocations. Canonical source compile+render
          # and artifact load+first-render workflows are measured separately by
          # ForkBenchmark, where every sample has isolated template caches.
          def run(compile_proc:, render_proc:, env_proc:, duration:, dump_proc: nil, load_proc: nil)
            artifact = !dump_proc.nil? && !load_proc.nil?
            half = artifact ? duration / 3.0 : duration / 2.0

            # ── 0. Artifact first-observation diagnostic ─────────────────
            if artifact
              GC.start(full_mark: true, immediate_sweep: true)
              compile_proc.call
              blob = dump_proc.call
              payload_bytes = blob.bytesize
              GC.start(full_mark: true, immediate_sweep: true)
              load_cold_1 = time_once { load_proc.call(blob) }
              cold_env = env_proc.call
              artifact_render_cold_1 = time_once { render_proc.call(cold_env) }
            end

            # ── 1. Cold renders (before any warmup) ──────────────────────
            # Snapshot YJIT before any render of this template
            yjit_before = yjit_snapshot

            GC.start(full_mark: true, immediate_sweep: true)
            compile_proc.call
            cold_env = env_proc.call
            cold_1 = time_once { render_proc.call(cold_env) }

            GC.start(full_mark: true, immediate_sweep: true)
            compile_proc.call
            cold_10 = Array.new(10) do
              env = env_proc.call
              time_once { render_proc.call(env) }
            end

            # ── 2. Warmup ────────────────────────────────────────────────
            warmup do
              compile_proc.call
              render_proc.call(env_proc.call)
            end

            # ── 3. Stabilize heap ────────────────────────────────────────
            GC.start(full_mark: true, immediate_sweep: true)
            GC.compact if GC.respond_to?(:compact)

            # ── 4. Allocations per op (median of 3) ─────────────────────
            compile_allocs = measure_allocs(3) { compile_proc.call }
            render_allocs  = measure_allocs(3, prepare: env_proc) { |env| render_proc.call(env) }

            # ── 5. Timed compile (production/default GC policy) ──────────
            compile_stats = timed_loop(half) { compile_proc.call }
            GC.start  # recover between phases

            # ── 6. Timed render (environment setup outside timer) ────────
            render_stats = timed_loop(half, prepare: env_proc) { |env| render_proc.call(env) }

            # Snapshot YJIT after all renders (cold + warm + timed)
            yjit_after = yjit_snapshot

            # ── 7. Artifact steady-state stage (GC ON — see docstring) ───
            if artifact
              GC.start
              load_allocs = measure_allocs(3) { load_proc.call(blob) }
              load_stats = timed_loop(half) { load_proc.call(blob) }
              # Leave ctx[:template] in the compiled (non-loaded) state
              compile_proc.call
            end

            result = build_result(
              compile_stats, render_stats,
              compile_allocs, render_allocs,
              cold_1, cold_10,
              yjit_delta(yjit_before, yjit_after, render_stats[:iters]),
            )
            if artifact
              result.merge!(
                artifact_bytes:         payload_bytes,
                load_median:            load_stats[:median],
                load_mean:              load_stats[:mean],
                load_min:               load_stats[:min],
                load_max:               load_stats[:max],
                load_stddev:            load_stats[:stddev],
                load_p95:               load_stats[:p95],
                load_iters:             load_stats[:iters],
                load_samples:           load_stats[:samples],
                load_batches:           load_stats[:batches],
                load_allocs:            load_allocs,
                load_cold_1:            load_cold_1,
                artifact_render_cold_1: artifact_render_cold_1,
              )
            end
            result
          rescue => e
            GC.enable rescue nil
            { error: e }
          end

          private

          def warmup
            t0 = clock
            n = 0
            deadline = t0 + WARMUP_SECONDS
            while n < WARMUP_MIN_ITERS || clock < deadline
              yield
              n += 1
            end
          end

          def time_once
            time_once_ns { yield } / 1_000_000_000.0
          end

          def time_once_ns
            t0 = clock_ns
            yield
            clock_ns - t0
          end

          # Any per-operation fixture returned by prepare is constructed before
          # the batch timer. Raw results contain one elapsed time per batch,
          # rather than thousands of rounded per-operation JSON values.
          def timed_loop(duration, prepare: nil)
            probe_input = prepare&.call
            probe = time_once { yield(probe_input) }
            batched_loop(duration, probe, prepare: prepare) { |input| yield(input) }
          end

          def batched_loop(duration, probe, prepare: nil)
            bs = [(TARGET_BATCH_SECS / [probe, 1e-7].max).to_i, 1].max
            bs = [bs, MAX_BATCH_SIZE].min

            times = []
            batches = []
            iters = 0
            deadline = clock + duration
            while iters < MAX_ITERS && clock < deadline
              inputs = Array.new(bs) { prepare.call } if prepare
              elapsed_ns = time_once_ns do
                bs.times { |index| yield(inputs && inputs[index]) }
              end
              times << (elapsed_ns / 1_000_000_000.0) / bs
              batches << { iterations: bs, elapsed_ns: elapsed_ns }
              iters += bs
            end
            stats(times, iters).merge(batches: batches)
          end

          def stats(times, iters = times.size)
            s = times.sort
            n = s.size
            m = times.sum / n.to_f
            {
              iters:   iters,
              samples: n,
              mean:    m,
              median:  pct(s, 50),
              min:     s.first,
              max:     s.last,
              stddev:  Math.sqrt(times.map { |t| (t - m)**2 }.sum / n.to_f),
              p75:     pct(s, 75),
              p95:     pct(s, 95),
              p99:     pct(s, 99),
            }
          end

          def measure_allocs(n, prepare: nil)
            counts = Array.new(n) do
              input = prepare&.call
              GC.start
              before = GC.stat(:total_allocated_objects)
              yield(input)
              GC.stat(:total_allocated_objects) - before
            end
            counts.sort[n / 2]
          end

          def build_result(cs, rs, ca, ra, cold_1, cold_10, yjit)
            cold_10_mean = cold_10.sum / cold_10.size.to_f
            cold_10_sorted = cold_10.sort
            {
              # Compile (warm)
              compile_median: cs[:median], compile_mean: cs[:mean],
              compile_min: cs[:min], compile_max: cs[:max],
              compile_stddev: cs[:stddev],
              compile_p75: cs[:p75], compile_p95: cs[:p95], compile_p99: cs[:p99],
              compile_iters: cs[:iters], compile_samples: cs[:samples],
              compile_batches: cs[:batches],
              compile_allocs: ca,

              # Render (warm steady-state)
              render_median: rs[:median], render_mean: rs[:mean],
              render_min: rs[:min], render_max: rs[:max],
              render_stddev: rs[:stddev],
              render_p75: rs[:p75], render_p95: rs[:p95], render_p99: rs[:p99],
              render_iters: rs[:iters], render_samples: rs[:samples],
              render_batches: rs[:batches],
              render_allocs: ra,

              # Cold render
              render_cold_1:       cold_1,
              render_cold_10_mean: cold_10_mean,
              render_cold_10_p50:  pct(cold_10_sorted, 50),
              render_cold_10_all:  cold_10,

              # YJIT delta during render (nil when not using YJIT)
              **yjit,

              error: nil,
            }
          end

          # Snapshot YJIT counters. Returns nil if no YJIT.
          def yjit_snapshot
            return nil unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
            s = RubyVM::YJIT.runtime_stats
            {
              compiled_iseqs: s[:compiled_iseq_count] || 0,
              compile_ns:     s[:compile_time_ns] || 0,
              invalidations:  s[:invalidation_count] || 0,
              code_size:      s[:inline_code_size] || 0,
            }
          end

          # Compute delta between two snapshots. Returns hash with yjit_ keys.
          def yjit_delta(before, after, iters)
            return {} unless before && after
            compiled  = after[:compiled_iseqs] - before[:compiled_iseqs]
            compile_ms = (after[:compile_ns] - before[:compile_ns]) / 1_000_000.0
            invalidations = after[:invalidations] - before[:invalidations]
            code_bytes = after[:code_size] - before[:code_size]

            result = {
              yjit_compiled_iseqs:  compiled,
              yjit_compile_time_ms: compile_ms,
              yjit_invalidations:   invalidations,
              yjit_code_bytes:      code_bytes,
            }
            # Per-iteration compile time (µs) — how much JIT overhead per render
            result[:yjit_compile_us_per_iter] = (compile_ms * 1000.0) / iters if iters > 0
            result
          end

          def pct(sorted, p)
            return sorted.first if sorted.size <= 1
            r = (p / 100.0) * (sorted.size - 1)
            lo = sorted[r.floor]
            hi = sorted[r.ceil]
            lo + (hi - lo) * (r - r.floor)
          end

          def clock
            clock_ns / 1_000_000_000.0
          end

          def clock_ns
            Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
          end
        end

        # ── Display helpers (all take seconds) ───────────────────────────

        def self.fmt(seconds)
          return "—" if seconds.nil? || seconds == 0
          if seconds >= 1       then "%.2fs"  % seconds
          elsif seconds >= 0.01 then "%.1fms" % (seconds * 1e3)
          elsif seconds >= 1e-3 then "%.2fms" % (seconds * 1e3)
          elsif seconds >= 1e-6 then "%.0fµs" % (seconds * 1e6)
          else                       "%.0fns" % (seconds * 1e9)
          end
        end

        def self.fmt_iters(n)
          return "0" if n.nil? || n == 0
          if    n >= 1e6 then "%.1fM" % (n / 1e6)
          elsif n >= 1e3 then "%.1fk" % (n / 1e3)
          else                n.to_s
          end
        end

        def self.fmt_allocs(n)
          return "0" if n.nil? || n == 0
          if n >= 1e6 then "%.1fM" % (n / 1e6)
          elsif n >= 1e4 then "%.1fk" % (n / 1e3)
          else n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
          end
        end

        # A slightly more precise format for benchmark result tables.
        def self.fmt_metric(seconds)
          return "—" if seconds.nil?
          if seconds >= 1
            "%.3f s" % seconds
          elsif seconds >= 0.01
            "%.2f ms" % (seconds * 1e3)
          elsif seconds >= 1e-3
            "%.3f ms" % (seconds * 1e3)
          elsif seconds >= 1e-6
            "%.1f µs" % (seconds * 1e6)
          else
            "%.0f ns" % (seconds * 1e9)
          end
        end

        def self.fmt_bytes(bytes)
          return "—" if bytes.nil?
          return "#{bytes} B" if bytes < 1024
          return "%.1f KiB" % (bytes / 1024.0) if bytes < 1024 * 1024
          "%.1f MiB" % (bytes / (1024.0 * 1024.0))
        end

        # Compact distribution view for raw ns samples or per-operation
        # seconds. Downsamples long runs into equal-width buckets.
        def self.sparkline(values, width: 12)
          values = Array(values).compact.map(&:to_f)
          return "" if values.empty?

          if values.size > width
            bucket_size = values.size.fdiv(width)
            values = width.times.map do |index|
              from = (index * bucket_size).floor
              to = [((index + 1) * bucket_size).floor, from + 1].max
              bucket = values[from...to]
              bucket.sum / bucket.size
            end
          end

          low, high = values.minmax
          return "▄" * values.size if low == high

          glyphs = "▁▂▃▄▅▆▇█"
          values.map do |value|
            index = (((value - low) / (high - low)) * (glyphs.length - 1)).round
            glyphs[index]
          end.join
        end

        def self.batch_samples_seconds(batches)
          Array(batches).filter_map do |sample|
            iterations = sample[:iterations] || sample["iterations"]
            elapsed_ns = sample[:elapsed_ns] || sample["elapsed_ns"]
            elapsed_ns / 1_000_000_000.0 / iterations if iterations.to_i > 0 && elapsed_ns
          end
        end

        def self.stability(mean, stddev)
          return ["—", 0.0] unless mean.to_f.positive? && stddev
          cv = stddev / mean
          label = if cv <= 0.03
            "steady"
          elsif cv <= 0.08
            "stable"
          elsif cv <= 0.15
            "lively"
          else
            "noisy"
          end
          [label, cv]
        end

        # Keep old names as aliases
        class << self
          alias_method :format_time_short, :fmt
          alias_method :format_iters, :fmt_iters
          alias_method :format_allocs, :fmt_allocs
        end

        # Remove nil values recursively without rounding measurements. JSON
        # numbers preserve enough precision for the compatibility second-based
        # fields, while raw benchmark batches are emitted as integer ns.
        def self.compact(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, child), out|
              next if child.nil?
              out[key] = compact(child)
            end
          when Array
            value.map { |child| compact(child) }
          else
            value
          end
        end
      end
    end
  end
end
