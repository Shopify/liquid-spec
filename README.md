# liquid-spec

[![CI](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml/badge.svg)](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml)

**liquid-spec is both an acceptance suite and an implementation system for
[Liquid](https://github.com/Shopify/liquid).** It can verify an existing parser and
renderer, but it is also designed to guide a human or coding agent from an empty project
to a production-ready Liquid implementation, one observable behavior at a time.

The suite contains thousands of executable examples drawn from Shopify's reference
implementation, a curated beginner ramp, parser-error matrices, Dawn theme fixtures,
and production recordings. The adapter boundary works with any implementation strategy
and, over JSON-RPC, any programming language.

## More Than a Conformance Suite

A conventional conformance suite answers **“is this implementation compatible?”**
liquid-spec also answers:

- **What is the smallest useful behavior to implement next?**
- **Why does Liquid behave this way?**
- **Which earlier behavior did this change regress?**
- **How far has the implementation progressed from a text passthrough to production
  compatibility?**

Every spec has a `complexity` from 0 to 1000. Foundation cases come first: empty input,
literal text, and object output. Variables, filters, control flow, loops, scopes,
partials, parser modes, compatibility quirks, and production recordings follow. The
runner reports the lowest-complexity failures as **“Next best specs to work on”** and
shows an implementation hint with each failure.

That turns the suite into an executable curriculum:

```text
run liquid-spec
      │
      ▼
read the first failure + hint ──► implement the general rule
      ▲                                      │
      └──────── rerun every earlier spec ◄───┘
```

`Complexity level cleared: 70 of 1000` means all exercised levels before the first
failing level are solid. It is deliberately more honest than a raw pass count: a toy
renderer may accidentally pass hundreds of empty-output cases without clearing the
beginner ramp.

## Why the Agent Loop Works

liquid-spec gives an agent the ingredients that open-ended “implement Liquid” prompts
normally lack:

1. **A stable, observable contract.** Specs describe templates, input values,
   filesystems, expected output, and expected errors—not a required internal
   architecture. An AST interpreter, bytecode VM, compiler, or transpiler can follow the
   same path.
2. **A prerequisite-ordered search space.** Complexity scoring reduces a language-sized
   task to a small next step. Later behavior is introduced after the semantics it builds
   on.
3. **Just-in-time implementation guidance.** Curated failures include actionable hints,
   and `liquid-spec docs` supplies deeper implementer guides for values, grammar, scopes,
   filters, loops, partials, parsing, and quirks.
4. **A tight verification loop.** Every change is immediately checked against all earlier
   behavior. The agent cannot make apparent progress by silently trading one feature for
   another.
5. **Reference and production evidence.** `liquid-spec tools eval --compare` answers ambiguous
   questions against Shopify/liquid, while integration tests and production recordings
   prevent a classroom-only implementation from looking complete.
6. **Explicit scope.** Feature gates distinguish portable Liquid, legacy parser modes,
   Ruby-specific behavior, and Shopify extensions. Unsupported features are visible debt,
   not noise hidden among failures.
7. **Machine-readable operation.** `--json`, name/suite filters, inspection, and focused
   eval commands let an agent gather precise evidence and iterate without scraping an
   unstructured test log.

`liquid-spec init` makes this workflow agent-ready. It generates disposable adapter
shims plus an `AGENTS.md` that explains the loop, hard rules, architecture advice,
protocol, feature gates, and documentation commands. Your Liquid package remains a
standalone library; the adapter exists only to let liquid-spec exercise it.

## How Acceptance Testing Works

```text
YAML behavior specs
  (template, environment, filesystem, expected output/error)
                           │
                           ▼
                  liquid-spec runner
                           │
                  compile + render calls
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       direct Ruby adapter       JSON-RPC adapter
                                  (TypeScript, Rust,
                                   Go, Python, ...)
              │                         │
              └────────────┬────────────┘
                           ▼
                  your Liquid engine
```

For each case, liquid-spec compiles the source, renders it with the recorded environment
and filesystem, then compares output or errors with the accepted behavior. The bridge is
small enough that results describe the engine rather than the test integration.

## Installation

Add to your Gemfile:

```ruby
gem "liquid-spec", git: "https://github.com/Shopify/liquid-spec"
```

Then run:

```bash
bundle install
```

Or install directly from GitHub:

```bash
gem install specific_install
gem specific_install https://github.com/Shopify/liquid-spec
```

## Quick Start

```bash
# Generate both adapter choices and an agent implementation guide.
liquid-spec init

# Read the curriculum, then run the adapter for your language.
liquid-spec docs curriculum
liquid-spec run specs/adapter.rb                 # Ruby
liquid-spec run specs/adapter-jsonrpc.rb \
  --command="your-liquid-jsonrpc-server"           # any other language
```

The first failure is the next lesson. Implement the behavior described by its hint and
rerun the same command. Re-running `init` leaves identical generated files alone; when a
target differs, it asks before overwriting and defaults to **No**.

## Full CLI Example: Ask an Agent to Build Liquid in TypeScript

The complete bootstrap is intentionally small. Start in an empty directory:

```bash
mkdir liquid-typescript
cd liquid-typescript

gem install specific_install
gem specific_install https://github.com/Shopify/liquid-spec

# Creates specs/adapter.rb, specs/adapter-jsonrpc.rb, and AGENTS.md.
# The JSON-RPC adapter is the bridge the TypeScript implementation will use.
liquid-spec init

codex -p "/goal Implement a full production-ready Liquid implementation in TypeScript. \
Read AGENTS.md first. Use specs/adapter-jsonrpc.rb only as the test bridge; build the \
engine as a standalone TypeScript library. Ask liquid-spec for guidance on the next \
steps, implement the general behavior behind each lowest-complexity failure, and rerun \
the suite after every change. Do not special-case specs or hide required behavior with \
missing_features. Keep going until liquid-spec reports Complexity level cleared: \
1000 of 1000 for every applicable suite."
```

That is enough context because `liquid-spec init` wrote the detailed operating manual
into `AGENTS.md`. The agent can discover and use the whole feedback loop itself:

```bash
# After setting DEFAULT_COMMAND in specs/adapter-jsonrpc.rb to the TypeScript server:
liquid-spec run specs/adapter-jsonrpc.rb
liquid-spec tools inspect specs/adapter-jsonrpc.rb -n "the_failing_spec"
liquid-spec docs curriculum
liquid-spec docs core-abstractions
cat scratch.yml | liquid-spec tools eval specs/adapter-jsonrpc.rb --compare
liquid-spec run specs/adapter-jsonrpc.rb --json
```

The generated JSON-RPC adapter initially opts out of capabilities that cannot be carried
portably or have not been wired yet, such as Ruby-only values, standard test drops, and
Shopify extensions. Reaching `1000 of 1000` means every spec selected for the adapter
passes; a production target also requires reviewing `missing_features` and removing each
entry that belongs in that target. Use `liquid-spec tools features` to audit that scope.

For a human-driven implementation, use exactly the same loop: run, read the first hint,
implement, and rerun. `liquid-spec docs json-rpc-protocol` documents the four subprocess
methods (`initialize`, `compile`, `render`, and `quit`).

## Writing an Adapter

An adapter is a small Ruby file that tells liquid-spec how to use your implementation:

```ruby
#!/usr/bin/env ruby
require "liquid/spec/cli/adapter_dsl"

# Load your implementation; ctx carries compiled state between callbacks.
LiquidSpec.setup do |ctx|
  require "my_liquid"
end

# Declare what your adapter can't handle (default: run everything)
LiquidSpec.configure do |config|
  config.missing_features = [:shopify_tags, :shopify_filters]
end

# Parse template source and retain the result in the adapter context.
LiquidSpec.compile do |ctx, source, options|
  # options includes: :line_numbers, :error_mode
  ctx[:template] = MyLiquid::Template.parse(source, **options)
end

# Render the template stored by compile or load_artifact.
LiquidSpec.render do |ctx, assigns, options|
  # assigns = variables hash
  # options includes: :registers, :strict_errors, :error_mode, :exception_renderer
  ctx[:template].render(assigns, **options)
end
```

The `options` hash in render includes:
- `:registers` - Hash with `:file_system` and `:template_factory`
- `:strict_errors` - If true, raise errors; if false, render them inline
- `:exception_renderer` - Custom exception handler (optional)


### JSON-RPC adapters for non-Ruby implementations

Use `liquid-spec init --jsonrpc my_adapter.rb` when your Liquid engine is written in Rust, Go, Python, Node.js, or another language. The generated Ruby adapter launches your server as a subprocess and talks JSON-RPC over stdin/stdout.

Key setup points:

- Your server implements `initialize`, `compile`, `render`, and `quit`.
- Server debug logs go to stderr; stdout must contain only newline-delimited JSON-RPC messages.
- The adapter controls spec selection with `config.missing_features`; server-reported `features` are informational.
- Minimal JSON-RPC adapters should usually opt out of unsupported or non-portable features such as `:drops`, `:ruby_types`, `:ruby_drops`, `:drop_class_output`, `:self_environment_shadowing`, `:binary_data`, and `:template_factory`, plus Shopify-specific features.
- Remove `:drops` when the engine supports the standard test-drop library. Bidirectional runtime objects can use the protocol's `drop_get`, `drop_call`, and `drop_iterate` callbacks.
- Read `docs/json-rpc-protocol.md` for the exact message format and error-handling rules.

```bash
liquid-spec init --jsonrpc my_adapter.rb
liquid-spec run my_adapter.rb --command="./my-liquid-server"
liquid-spec run my_adapter.rb --json --list-passed > results.json
```

### Optional: compiled-artifact protocol

Some Liquid implementations compile source once, store executable bytecode or
an equivalent compiled representation in a shared cache, and load those bytes
in application processes that never receive the source. `compile` and `render`
alone cannot measure that important production path: parsing again is not an
artifact-cache hit, while repeatedly rendering a resident template omits the
load and first-use costs.

If your implementation has such a persistent compiled format, declare both
hooks:

```ruby
# Called immediately after LiquidSpec.compile, before the template is rendered.
# Return the exact binary String you would put in memcache, a database, etc.
LiquidSpec.dump_artifact do |ctx|
  ctx[:template].to_artifact
end

# Called in a runtime-loaded, template-cold fork that has the bytes but no source.
# Restore all adapter state expected by the regular LiquidSpec.render hook.
LiquidSpec.load_artifact do |ctx, bytes, _options|
  ctx[:template] = MyLiquid::Artifact.load(bytes)
end
```

The contract is deliberately production-oriented:

1. `dump_artifact` receives the state produced by `compile` and must return a
   binary-safe `String`. It is invoked before any validation render, because
   rendering is allowed to mutate template runtime state.
2. The returned bytes must contain all immutable compile-time information needed
   to load the template without its source. Do not capture assigns, observed
   values, request objects, or render-time object shapes.
3. `load_artifact` must leave `ctx` in the same renderable state that `compile`
   would. The source is unavailable. Its third argument is the runtime options
   Hash that the following `render` hook will receive; most loaders ignore it.
4. Assigns, registers, and runtime filesystems are still supplied to the normal
   `render` hook for every call; they are not part of the artifact.

With both hooks, `--bench` validates the dump → load → render roundtrip, reports
raw artifact bytes and steady-state load diagnostics, and measures the atomic
artifact-load + first-render workflow in 30 forked children. The parent runtime
is loaded but has never seen the benchmark template, and fork/IPC work is outside
the timer. This models a shared artifact fetched into memory in another process.

`--bench` warns when either hook is missing because artifact size and
load+first-render results will be omitted. Implementations without a persistent
compiled format may leave the hooks absent; the warning documents that the
benchmark is then limited to source compile and resident render paths.

### Optional: local suites

Projects can ship their own spec/benchmark suites alongside their adapter:
any `./specs/<name>/suite.yml` directory in the invoking project is
discovered next to the gem's builtin suites and selected the same way
(`-s <name>`). Set `timings: true` in `suite.yml` to make it benchmarkable
with `liquid-spec bench ADAPTER -s <name>`, and `default: false` to keep it
out of regular runs.

## Test Suites

| Suite | Tests | Description |
|-------|-------|-------------|
| **basics** | 940 | Essential Liquid features - start here! Ordered by complexity with implementation hints |
| **liquid_ruby** | 2,097 | Core Liquid specs from [Shopify/liquid](https://github.com/Shopify/liquid) integration tests |
| **liquid_ruby_lax** | 121 | Lax-mode reference behavior |
| **parser_errors** | 1,901 | Strict parser error compatibility and mutation matrices |
| **partials** | 12 | Include/render focused compatibility specs and timings |
| **benchmarks** | 10 | Storefront, dynamic-partial, `{% liquid %}`, and Shopify-theme performance cases |
| **shopify_production_recordings** | 2,260 | Recorded behavior from Shopify's production Liquid compiler |
| **shopify_theme_dawn** | 26 | Real-world templates from [Shopify Dawn](https://github.com/Shopify/dawn) theme |

### The Basics Suite

If you're building a new Liquid implementation, **start with the basics suite**. It runs first and covers all fundamental features from the [official Liquid documentation](https://shopify.github.io/liquid/).

Specs are ordered by complexity so you can implement features progressively. The goal is a smooth ramp: a toy renderer should pass only the trivial first specs, then fail on a small, actionable next behavior.

| Complexity | Features |
|------------|----------|
| 0-1 | Empty template and literal passthrough |
| 5-20 | First object output, literal strings/numbers/booleans/nil |
| 30-50 | Variables, missing variables, very simple filters, assign |
| 55-65 | Basic if/else/unless and simple boolean composition |
| 70-100 | Gentle loops, comparisons, forloop basics, capture, simple case/when |
| 105-150 | Common filters/tags, comments/raw, interrupts, loop modifiers, whitespace control |
| 160-220 | Generated filter breadth, truthy/falsy edges, cycle/tablerow, first partials/filesystem |
| 230-400 | Long-tail standard behavior and parser/scope/filesystem edge cases |
| 500-900 | Mature compatibility: parser mutations, resource-limit accounting, recursion/deep nesting, date/time/Ruby quirks |
| 1000 | Production recordings and unscored specs |

Each non-trivial spec includes a detailed `hint` explaining how the feature should be implemented. If the first failure is surprising or unactionable, the spec probably needs a better hint or a higher complexity score.

**Read `Complexity level cleared`, not just total passes.** A naive adapter that always returns `""` can accidentally pass many later specs whose expected output is empty, but its cleared complexity level should remain at 0. The complexity-level line tells you how far the implementation progressed through the ordered curriculum.

### Feature-Based Suite Selection

Suites marked as default run unless you select one explicitly with `-s`. Declare what
your adapter cannot handle to skip specs that require those capabilities:

```ruby
LiquidSpec.configure do |config|
  # Run everything (default — empty denylist)
  config.missing_features = []

  # Skip Shopify-specific specs (for adapters without Shopify extensions)
  config.missing_features = [:shopify_tags, :shopify_objects, :shopify_filters]
end
```

## Generated Adversarial Coverage

After the recorded ramp passes, generate nearby cases and compare them directly with
Shopify/liquid:

```bash
liquid-spec tools mutate adapter.rb --around=for_loops --limit=100
liquid-spec tools fuzz adapter.rb --seed=1234 --rounds=500 --minimize
liquid-spec tools stress adapter.rb --depth=64 --repetitions=100
```

`mutate` deterministically changes existing specs; `fuzz` reproducibly chains random
mutations; `stress` generates bounded valid nesting and repetition. Differences are saved
as runnable YAML regression specs by default. These commands cover whitespace controls,
literal boundaries, lookups, filters, conditionals, loop options, malformed block
structure, opaque bodies, Unicode, and newlines.

This is differential corpus mutation, not native coverage-guided fuzzing. See
`liquid-spec docs adversarial` for comparison semantics, seed selection, JSON output,
minimization, and how to curate a generated discovery into the permanent suite.

## CLI Reference

```bash
liquid-spec COMMAND [options]

Core commands:
  liquid-spec init [FILE]                 Generate adapters and AGENTS.md
  liquid-spec docs [NAME]                 Read implementer documentation
  liquid-spec run ADAPTER                 Run the acceptance ramp
  liquid-spec bench [ADAPTER]             Benchmark implementations

Tool collection (`liquid-spec tools help`):
  liquid-spec tools inspect ADAPTER       Inspect matching specs in detail
  liquid-spec tools eval ADAPTER          Evaluate one YAML spec
  liquid-spec tools matrix                Compare adapters side-by-side
  liquid-spec tools test                  Exercise bundled example adapters
  liquid-spec tools features              Audit feature tags and scope
  liquid-spec tools report                Analyze benchmark results
  liquid-spec tools check                 Run every verifier
  liquid-spec tools mutate ADAPTER        Deterministic differential mutations
  liquid-spec tools fuzz ADAPTER          Seeded differential fuzz-style testing
  liquid-spec tools stress ADAPTER        Bounded structural stress

Run options:
  -n, --name PATTERN       Only run specs matching PATTERN
  -s, --suite SUITE        Run specific suite (liquid_ruby, benchmarks, etc.)
  -c, --compare            Compare output against reference liquid-ruby
  -v, --verbose            Show detailed output
  -l, --list               List available specs
  --list-suites            List available test suites
  --max-failures N         Stop after N failures (default: 5)
  --no-max-failures        Run all specs without stopping
  --list-passed           List specs that passed after the run (ramp/debug audits)
  --json                  Output a single JSON summary (for tools)
  --jsonl                 Output one JSON event per line (for benchmark streaming/tools)
  -h, --help               Show help

Examples:
  liquid-spec run my_adapter.rb                    # Run all applicable specs
  liquid-spec run my_adapter.rb -n for_tag         # Run specs matching 'for_tag'
  liquid-spec run my_adapter.rb -s liquid_ruby     # Run only liquid_ruby suite
  liquid-spec run my_adapter.rb --compare          # Compare against reference
  liquid-spec run my_adapter.rb --no-max-failures  # See all failures
  liquid-spec bench my_adapter.rb -n storefront      # Benchmark adapter vs reference
  liquid-spec tools check                            # Run every spec verifier
  liquid-spec tools features                         # Audit supported feature scope
  liquid-spec tools inspect my_adapter.rb -n "case"  # Debug specific specs
  liquid-spec tools mutate my_adapter.rb --around=for_loops
  liquid-spec tools fuzz my_adapter.rb --seed=1234 --json
```


### Auditing the Ramp with Dumb Adapters

When changing complexity scores or adding early specs, test the harness with intentionally bad adapters:

- an adapter that returns the template source unchanged
- an adapter that always returns `""`
- an adapter that raises during compile or render

Use `--list-passed` to see accidental passes and `--json` for machine-readable analysis:

```bash
liquid-spec run /tmp/echo_adapter.rb --list-passed
liquid-spec run /tmp/empty_adapter.rb --json --list-passed > empty-results.json
```

A source-echo adapter should only pass raw-text specs before failing on first object output. An always-empty adapter may pass many empty-output specs, so judge progress by `Complexity level cleared` (or JSON `max_complexity_reached`), not by total passes.

### Matrix Command

The `matrix` command runs specs across multiple adapters simultaneously and shows differences between implementations. This is useful for comparing behavior across different Liquid implementations or configurations.

```bash
liquid-spec tools matrix [options]

Options:
  --all                    Run all available adapters from examples/
  --adapters=LIST          Comma-separated list of adapters
  --reference=NAME         Reference adapter (default: liquid_ruby)
  -n, --name PATTERN       Filter specs by name pattern
  -s, --suite SUITE        Spec suite to run
  --max-failures N         Stop after N differences (default: 10)
  --no-max-failures        Show all differences
  -v, --verbose            Show detailed output

Examples:
  # Compare all bundled adapters
  liquid-spec tools matrix --all

  # Compare specific adapters
  liquid-spec tools matrix --adapters=liquid_ruby,liquid_ruby_lax

  # Compare adapters on specific tests
  liquid-spec tools matrix --adapters=liquid_ruby,liquid_c -n truncate
```

Output shows which adapters produce different results for each spec:

```
Running 100 specs: ....F....F.. done

======================================================================
DIFFERENCES
======================================================================
----------------------------------------------------------------------
1. TruncateTest#test_truncate_with_custom_ellipsis

Template:
  {{ text | truncate: 10, "..." }}

Adapters: liquid_ruby
Output:
  "Hello w..."

Adapters: liquid_c
Output:
  "Hello wo..."
======================================================================
```

### Benchmarking

liquid-spec includes a benchmark suite for measuring and comparing implementation performance. Benchmarks measure **compile** and **render** times separately, with statistical analysis including mean, standard deviation, and min/max ranges.

#### Single Adapter Benchmarks

Run benchmarks against a single adapter to measure its performance:

```bash
liquid-spec bench examples/liquid_ruby.rb -n leaderboard
```

Abbreviated output:
```text
liquid_ruby — Benchmarks
Ruby 4.x (no-jit) │ 1 specs │ 5s/spec

Benchmark 1/1: liquid_tag_leaderboard
  Parse  (mean ± σ):  270µs ± 38µs   [893 allocs, 9.3k runs]
  Render (mean ± σ):  564µs ± 116µs  [926 allocs, 4.4k runs]
  Range  (min … max): 530µs … 3.79ms [4.4k runs]
  Cold   (@1 / @10):  664µs / 618µs  (1.2x vs warm)

1 passed
```

Benchmarks report parse/render distributions, allocation counts, cold-render behavior,
and iteration totals. GC is disabled during timing to reduce measurement jitter.

#### Multi-Adapter Performance Comparison

Compare performance across different implementations using the core `bench` command:

```bash
liquid-spec bench --adapters=liquid_ruby,liquid_ruby_lax
```

Each benchmark runs against all adapters. The command prints their measurements together,
then reports geometric-mean parse and render comparisons across common specs. When a
comparison mixes inline adapters with JSON-RPC adapters, `bench` warns that subprocess
and protocol overhead make the timings non-equivalent.

```text
Benchmark 1/10: storefront_product_page
  liquid_ruby      Parse ...  Render ...
  liquid_ruby_lax  Parse ...  Render ...
  → liquid_ruby is 1.08x faster

──────────────────────────────────────────────────────────────────────
Comparison (10 common specs, reference: liquid_ruby)

  Parse (geometric mean):
    liquid_ruby is 1.05x faster than liquid_ruby_lax
  Render (geometric mean):
    liquid_ruby_lax ≈ liquid_ruby
```

#### Benchmark Specs

The benchmark suite currently includes 10 realistic templates:

| Benchmark | Description |
|-----------|-------------|
| `bench_dynamic_partials` | Data-selected partials, loops, and three levels of nested includes |
| `bench_liquid_tag_inventory_report` | Inventory aggregation entirely inside a `{% liquid %}` block |
| `bench_liquid_tag_leaderboard` | Nested-loop ranking and formatting in `{% liquid %}` syntax |
| `bench_storefront_product_page` | Standard-Liquid product page with variants, reviews, and partials |
| `bench_storefront_collection_page` | Standard-Liquid collection browsing and product grids |
| `bench_storefront_cart_page` | Standard-Liquid cart totals, discounts, and line items |
| `bench_storefront_order_email` | Standard-Liquid transactional order email |
| `bench_storefront_cms_page` | Standard-Liquid content-management page |
| `shopify_theme_full_page` | Full Shopify Dream theme layout using Shopify filters |
| `shopify_theme_product_page` | Shopify Dream product page using Shopify filters |

Selecting these specs through `liquid-spec run ADAPTER -s benchmarks` checks correctness
without collecting timings; use `liquid-spec bench` for performance measurements.

#### Profiling with StackProf

Use `liquid-spec bench --profile` to generate StackProf profiles for detailed performance analysis:

```bash
# Single adapter profiling
liquid-spec bench examples/liquid_ruby.rb --profile

# Multi-adapter profiling
liquid-spec bench --adapters=liquid_ruby,liquid_c --profile
```

A single-adapter profile directory contains four dumps:

```text
/tmp/liquid-spec-profile-20260710_155637/
├── compile_cpu.dump
├── compile_object.dump
├── render_cpu.dump
└── render_object.dump
```

Inspect one with `stackprof /tmp/liquid-spec-profile-20260710_155637/render_cpu.dump`.

In multi-adapter bench mode, each adapter gets a separate directory such as
`/tmp/liquid-spec-profile-{timestamp}-liquid_ruby/`; the command prints every path.

Profile types:
- `*_cpu.dump` - CPU time profiles (where time is spent)
- `*_object.dump` - Object allocation profiles (where allocations happen)

### Quick Testing with `eval`

The `eval` tool lets you quickly test individual templates. Specs are passed via YAML
on stdin or `--spec=FILE`; add `--compare` to compare with the reference liquid-ruby
implementation and fill omitted expectations:

```bash
liquid-spec tools eval examples/liquid_ruby.rb --compare <<EOF
name: upcase-test
complexity: 20
template: "{{ x | upcase }}"
expected: "HI"
environment:
  x: hi
hint: "Test upcase filter on simple string variable"
EOF
```

Output:
```
upcase-test
Test upcase filter on simple string variable

Template: {{ x | upcase }}
Complexity: 20

✓ PASS (matches reference)
  "HI"

Saved to: /tmp/liquid-spec-2026-01-02.yml
```

When using `--compare` (the default), the `expected` field can be omitted - it will be filled from the reference implementation. If your implementation differs from the reference, you'll see a prominent message encouraging you to contribute the spec.

Specs are automatically saved to `/tmp/liquid-spec-{date}.yml` for easy contribution back to liquid-spec.

## Example Output

Default `run` output is intentionally concise: it shows the lowest-complexity failures
(the next specs to work on) and then one summary line.

Failing run:

```
$ liquid-spec run my_adapter.rb --max-failures 1

Next best specs to work on:

1) [c=5] object_string_literal
   Template:   "{{ 'world' }}"
   Expected:   "world"
   Got:        "{{ 'world' }}"

   Hint: The {{ }} syntax outputs the value of an expression...

Complexity level cleared: 1 of 5, 2 passes, 1 failures.
```

Successful run (counts depend on selected suites/features):

```
$ liquid-spec run my_adapter.rb
Complexity level cleared: 1000 of 1000, 1234 passes, 0 failures, 12 skipped.

Congrats! All run specs passed.
```

Use `-v` for preamble, per-suite progress, and skipped-suite details.

## Example Adapters

See the `examples/` directory:

- **`liquid_ruby.rb`** - Standard [Shopify/liquid](https://github.com/Shopify/liquid) gem
- **`liquid_ruby_lax.rb`** - Shopify/liquid configured for lax-mode compatibility specs
- **`liquid_ruby_shopify.rb`** - Shopify-flavored Liquid behavior
- **`json_rpc_ruby_liquid.rb`** - JSON-RPC adapter backed by Shopify/liquid
- **`liquid_c.rb`** / **`liquid_c_strict.rb`** - [liquid-c](https://github.com/Shopify/liquid-c) native extension examples
- **`liquid_ruby_yjit.rb`** / **`liquid_ruby_zjit.rb`** - Ruby JIT benchmark variants

```bash
liquid-spec run examples/liquid_ruby.rb
```

## Spec Format

Specs are YAML files with this structure:

```yaml
- name: AssignTest#test_assign_with_filter
  template: '{% assign foo = values | split: "," %}{{ foo[1] }}'
  environment:
    values: "foo,bar,baz"
  expected: "bar"
  complexity: 50
  hint: |
    The assign tag creates a variable. Filters can be used in the expression.
```

Each spec defines:
- **template** - Liquid source to compile and render
- **environment** - Variables available during rendering
- **expected** - Expected output string
- **complexity** - Optional: ordering hint (lower = simpler, runs first; defaults to 1000 and must not exceed 1000)
- **hint** - Optional: implementation guidance for this feature
- **error_mode** - Optional: `lax`, `strict`, `strict2`, or an array of compatible modes
- **filesystem** - Optional: mock files for include/render tags

## Development

```bash
# Clone
git clone https://github.com/Shopify/liquid-spec.git
cd liquid-spec

# Install dependencies
bundle install

# Run every verifier (the Rake task is equivalent)
liquid-spec tools check
rake check

# Unit tests for liquid-spec itself
rake test

# Run specs against the Shopify/liquid reference adapter
bundle exec rake run

# Regenerate specs from Shopify/liquid source
# (requires ../liquid directory with Shopify/liquid checked out)
bundle exec rake generate
```

### Regenerating Specs

The `rake generate` task:
1. Clones Shopify/liquid at the current version tag
2. Patches its test suite to capture template/expected pairs  
3. Runs the tests and records every `assert_template_result` call
4. Writes captured specs to `specs/liquid_ruby/`

This ensures specs stay synchronized with the reference implementation.

## License

MIT
