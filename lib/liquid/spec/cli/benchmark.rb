# frozen_string_literal: true

module Liquid
  module Spec
    module CLI
      # Shared benchmark infrastructure for runner.rb and matrix.rb.
      #
      # Design decisions:
      #   - Environment copies are pre-allocated OUTSIDE the hot loop
      #   - Warmup runs for >= 1 second to let JIT (YJIT/ZJIT) stabilize
      #   - GC is compacted once after warmup, then disabled per phase
      #   - GC is re-enabled between compile and render phases
      #   - Individual timings are recorded when ops are slow enough (>50µs)
      #   - Batch timings used for fast ops, with batch means stored
      #   - Percentiles (p50, p75, p95, p99) computed from samples
      #   - Allocations measured as median of 3 runs
      module Benchmark
        # Minimum warmup duration in seconds
        WARMUP_SECONDS = 1.0
        # Minimum warmup iterations
        WARMUP_MIN_ITERATIONS = 50
        # Target batch duration in seconds (for auto-sizing)
        TARGET_BATCH_SECONDS = 0.02
        # Max batch size to prevent huge batches for trivial ops
        MAX_BATCH_SIZE = 2000
        # Max iterations (generous — 500k should be enough for anyone)
        MAX_ITERATIONS = 500_000

        class << self
          # Run a complete benchmark for a single spec.
          #
          # compile_proc: -> { ... } called to compile the template
          # render_proc:  -> { ... } called to render (should NOT copy env itself)
          # env_proc:     -> { Hash } returns a fresh environment copy for each render
          # duration:     total seconds to spend benchmarking (split compile/render)
          #
          # Returns a result hash with all metrics, or { error: Exception }
          def run(compile_proc:, render_proc:, env_proc:, duration:)
            half = duration / 2.0

            # ── Warmup (both phases, lets JIT stabilize) ──
            warmup(WARMUP_SECONDS) do
              compile_proc.call
              render_proc.call(env_proc.call)
            end

            # ── Stabilize heap ──
            GC.start(full_mark: true, immediate_sweep: true)
            GC.compact if GC.respond_to?(:compact)

            # ── Measure allocations (median of 3) ──
            compile_allocs = measure_allocs(3) { compile_proc.call }
            render_allocs  = measure_allocs(3) { render_proc.call(env_proc.call) }

            # ── Benchmark compile ──
            GC.disable
            compile = timed_loop(half) { compile_proc.call }
            GC.enable

            # Let GC recover between phases
            GC.start

            # ── Benchmark render ──
            GC.disable
            render = timed_loop(half) { render_proc.call(env_proc.call) }
            GC.enable

            build_result(compile, render, compile_allocs, render_allocs)
          rescue => e
            GC.enable rescue nil
            { error: e }
          end

          private

          # Warm up for at least `seconds` and `WARMUP_MIN_ITERATIONS` iterations.
          def warmup(seconds)
            start = clock
            iterations = 0
            deadline = start + seconds
            while iterations < WARMUP_MIN_ITERATIONS || clock < deadline
              yield
              iterations += 1
            end
          end

          # Core timing loop. Returns raw samples array and iteration count.
          #
          # Auto-detects whether individual timing is feasible:
          # - If a single call takes >50µs, record individual times
          # - Otherwise, batch and record batch means
          def timed_loop(duration)
            # Probe single iteration time
            t0 = clock
            yield
            probe_time = clock - t0

            if probe_time > 0.00005  # >50µs — record individual times
              timed_loop_individual(duration) { yield }
            else
              timed_loop_batched(duration, probe_time) { yield }
            end
          end

          # Record each iteration individually (for slower ops)
          def timed_loop_individual(duration)
            times = []
            iterations = 0
            deadline = clock + duration

            while iterations < MAX_ITERATIONS && clock < deadline
              t0 = clock
              yield
              times << (clock - t0)
              iterations += 1
            end

            build_stats(times, iterations, batched: false)
          end

          # Batch iterations together (for fast ops <50µs)
          def timed_loop_batched(duration, probe_time)
            batch_size = [(TARGET_BATCH_SECONDS / [probe_time, 0.0000001].max).to_i, 1].max
            batch_size = [batch_size, MAX_BATCH_SIZE].min

            times = []  # Each entry is mean time per iteration for that batch
            iterations = 0
            deadline = clock + duration

            while iterations < MAX_ITERATIONS && clock < deadline
              t0 = clock
              batch_size.times { yield }
              elapsed = clock - t0
              times << (elapsed / batch_size)
              iterations += batch_size
            end

            build_stats(times, iterations, batched: true)
          end

          # Compute statistics from samples.
          def build_stats(times, iterations, batched:)
            sorted = times.sort

            {
              samples: times,
              sorted: sorted,
              iterations: iterations,
              mean: times.sum / times.size.to_f,
              stddev: stddev(times),
              min: sorted.first,
              max: sorted.last,
              median: percentile(sorted, 50),
              p75: percentile(sorted, 75),
              p95: percentile(sorted, 95),
              p99: percentile(sorted, 99),
              batched: batched,
            }
          end

          # Measure allocations. Runs `n` times and returns the median.
          def measure_allocs(n)
            counts = n.times.map do
              GC.start
              before = GC.stat(:total_allocated_objects)
              yield
              GC.stat(:total_allocated_objects) - before
            end
            counts.sort[counts.size / 2]  # median
          end

          def build_result(compile, render, compile_allocs, render_allocs)
            {
              compile_mean:    compile[:mean],
              compile_median:  compile[:median],
              compile_stddev:  compile[:stddev],
              compile_min:     compile[:min],
              compile_max:     compile[:max],
              compile_p75:     compile[:p75],
              compile_p95:     compile[:p95],
              compile_p99:     compile[:p99],
              compile_runs:    compile[:iterations],
              compile_allocs:  compile_allocs,
              render_mean:     render[:mean],
              render_median:   render[:median],
              render_stddev:   render[:stddev],
              render_min:      render[:min],
              render_max:      render[:max],
              render_p75:      render[:p75],
              render_p95:      render[:p95],
              render_p99:      render[:p99],
              render_runs:     render[:iterations],
              render_allocs:   render_allocs,
              error:           nil,
            }
          end

          def percentile(sorted, pct)
            return sorted.first if sorted.size <= 1
            rank = (pct / 100.0) * (sorted.size - 1)
            lower = sorted[rank.floor]
            upper = sorted[rank.ceil]
            lower + (upper - lower) * (rank - rank.floor)
          end

          def stddev(arr)
            m = arr.sum / arr.size.to_f
            variance = arr.map { |x| (x - m)**2 }.sum / arr.size.to_f
            Math.sqrt(variance)
          end

          def clock
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end
      end
    end
  end
end
