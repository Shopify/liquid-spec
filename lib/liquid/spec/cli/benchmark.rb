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
      #   5. Timed phase (GC disabled): auto-selects individual timing for
      #      slow ops (>50µs) or batched timing for fast ops. Records every
      #      sample so percentiles are real, not averaged.
      #   6. GC re-enabled between compile and render phases.
      #
      # All times are in seconds. Callers use format helpers for display.
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
          # @return [Hash] result with all metrics, or { error: Exception }
          def run(compile_proc:, render_proc:, env_proc:, duration:)
            half = duration / 2.0

            # ── 1. Cold renders (before any warmup) ──────────────────────
            GC.start(full_mark: true, immediate_sweep: true)
            compile_proc.call
            cold_1 = time_once { render_proc.call(env_proc.call) }

            GC.start(full_mark: true, immediate_sweep: true)
            compile_proc.call
            cold_10 = Array.new(10) { time_once { render_proc.call(env_proc.call) } }

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
            render_allocs  = measure_allocs(3) { render_proc.call(env_proc.call) }

            # ── 5. Timed compile (GC off) ────────────────────────────────
            GC.disable
            compile_stats = timed_loop(half) { compile_proc.call }
            GC.enable
            GC.start  # recover between phases

            # ── 6. Timed render (GC off, YJIT delta tracked) ────────────
            yjit_before = yjit_snapshot
            GC.disable
            render_stats = timed_loop(half) { render_proc.call(env_proc.call) }
            GC.enable
            yjit_after = yjit_snapshot

            build_result(
              compile_stats, render_stats,
              compile_allocs, render_allocs,
              cold_1, cold_10,
              yjit_delta(yjit_before, yjit_after, render_stats[:iters]),
            )
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
            t0 = clock
            yield
            clock - t0
          end

          # Auto-select individual vs batch timing.
          def timed_loop(duration)
            probe = time_once { yield }

            if probe > 0.00005  # > 50µs → individual
              individual_loop(duration) { yield }
            else
              batched_loop(duration, probe) { yield }
            end
          end

          def individual_loop(duration)
            times = []
            deadline = clock + duration
            while times.size < MAX_ITERS && clock < deadline
              times << time_once { yield }
            end
            stats(times)
          end

          def batched_loop(duration, probe)
            bs = [(TARGET_BATCH_SECS / [probe, 1e-7].max).to_i, 1].max
            bs = [bs, MAX_BATCH_SIZE].min

            times = []
            iters = 0
            deadline = clock + duration
            while iters < MAX_ITERS && clock < deadline
              t0 = clock
              bs.times { yield }
              times << (clock - t0) / bs
              iters += bs
            end
            stats(times, iters)
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

          def measure_allocs(n)
            counts = Array.new(n) do
              GC.start
              before = GC.stat(:total_allocated_objects)
              yield
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
              compile_allocs: ca,

              # Render (warm steady-state)
              render_median: rs[:median], render_mean: rs[:mean],
              render_min: rs[:min], render_max: rs[:max],
              render_stddev: rs[:stddev],
              render_p75: rs[:p75], render_p95: rs[:p95], render_p99: rs[:p99],
              render_iters: rs[:iters], render_samples: rs[:samples],
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
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

        # Keep old names as aliases
        class << self
          alias_method :format_time_short, :fmt
          alias_method :format_iters, :fmt_iters
          alias_method :format_allocs, :fmt_allocs
        end
      end
    end
  end
end
