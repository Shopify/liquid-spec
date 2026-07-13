# liquid-spec

> The Rust rewrite is the v2 implementation path. It drives every Liquid engine
> through the JSON-RPC v2 adapter protocol; Ruby adapter DSLs and protocol-v1
> callbacks are retained only in the legacy Ruby release. Build the new binary
> with `cargo build -p liquid-spec-cli --bin liquid-spec` and run it as
> `target/debug/liquid-spec`.

The Rust CLI keeps the acceptance curriculum and the familiar `init`, `docs`,
`check`, `bench`, and `tools` commands. `run` remains a compatibility alias for
`check`. `liquid-spec init` creates a
`liquid-spec.toml` adapter manifest, an executable `adapter.ts` protocol demo, and
`AGENTS.md`; adapters are launched as external newline-delimited JSON-RPC v2 processes.
`--compare` uses a separately
configured Ruby/liquid JSON-RPC server when reference behavior is needed.

[![CI](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml/badge.svg)](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml)

**liquid-spec is both an acceptance corpus and an implementation system for
[Liquid](https://github.com/Shopify/liquid).** It can verify an existing parser and
renderer, but it is also designed to guide a human or coding agent from an empty project
to a production-ready Liquid implementation, one observable behavior at a time.

The corpus contains thousands of executable examples drawn from Shopify's reference
implementation, a curated beginner ramp, parser-error matrices, Dawn theme fixtures,
and production recordings. The adapter boundary works with any implementation strategy
and, over JSON-RPC, any programming language.

## More Than a Conformance Corpus

A conventional conformance corpus answers **“is this implementation compatible?”**
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

That turns the corpus into an executable curriculum:

```text
liquid-spec check
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
7. **Machine-readable operation.** `--json`, name/namespace filters, inspection, and focused
   eval commands let an agent gather precise evidence and iterate without scraping an
   unstructured test log.

`liquid-spec init` makes this workflow agent-ready. It generates a documented
source-echo `adapter.ts` protocol demo plus an `AGENTS.md` that explains the loop,
hard rules, architecture advice, protocol, feature gates, and documentation commands.
Your Liquid package remains a standalone library; the adapter exists only to let
liquid-spec exercise it.

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
       JSON-RPC adapter          JSON-RPC reference adapter
       (TypeScript, Rust,         (Ruby/liquid or another
        Go, Python, ...)          implementation)
              │                         │
              └────────────┬────────────┘
                           ▼
                  your Liquid engine
```

For each case, liquid-spec compiles the source, renders it with the recorded environment
and filesystem, then compares output or errors with the accepted behavior. The bridge is
small enough that results describe the engine rather than the test integration.

## Installation

Build the Rust binary:

```bash
cargo build --release -p liquid-spec-cli --bin liquid-spec
install target/release/liquid-spec ~/.local/bin/liquid-spec
```

The binary reads the built-in `specs/` directory shipped beside a release package
and embeds the high-signal documentation. During repository development, it reads
the checkout; set `LIQUID_SPEC_ROOT` or `LIQUID_SPEC_DOCS` to use another corpus.

The older Ruby gem remains available for protocol-v1 migration, but it is not needed
by the Rust runner or by non-Ruby Liquid implementations.

## Quick Start

```bash
# Creates liquid-spec.toml, adapter.ts, and AGENTS.md.
liquid-spec init

# With no subcommand, the manifest's `default = "check"` action runs the
# generated candidate adapter. Check options can be supplied directly too.
liquid-spec
liquid-spec -n assign

# Every implementation is an external JSON-RPC v2 process.
liquid-spec docs curriculum
liquid-spec check -- ./my-liquid-server

# Or name a repeatable command from liquid-spec.toml.
liquid-spec check --adapter candidate
liquid-spec tools protocol --adapter candidate
liquid-spec bench --adapter candidate
```

The runner performs the v2 protocol gate before loading Liquid specs. `check` evaluates
the full selected corpus, and the first lowest-complexity failure is the next
implementation lesson. Spec failures are observational: after the protocol gate
succeeds, the command exits 0 even when specs fail. Each check overwrites a
deterministically named report under `/tmp/liquid-spec-check-<hash>.txt`, containing
all passes and failures; human output points to it with `[all failures in ...]`.
`--compare` starts the separately configured Ruby/liquid JSON-RPC reference adapter;
the Rust binary never embeds Liquid.

The manifest and command line are equivalent configuration surfaces: explicit
subcommands and flags override `default`/`default_adapter` from `liquid-spec.toml`,
and `--config PATH` selects another manifest. The generated `adapter.ts` is a
source-echo protocol demo; replace its compile/render implementation as your Liquid
engine grows.

## Full CLI Example: Ask an Agent to Build Liquid in TypeScript

The complete bootstrap is intentionally small. Start in an empty directory:

```bash
mkdir liquid-typescript
cd liquid-typescript

# Creates liquid-spec.toml, adapter.ts, and AGENTS.md.
liquid-spec init

codex -p "/goal Implement a full production-ready Liquid implementation in TypeScript. \
Read AGENTS.md first; implement the JSON-RPC v2 server as the only test bridge; build the \
engine as a standalone TypeScript library. Ask liquid-spec for guidance on the next \
steps, implement the general behavior behind each lowest-complexity failure, and rerun \
the corpus after every change. Do not special-case specs or hide required behavior with \
missing_features. Keep going until liquid-spec reports Complexity level cleared: \
1000 of 1000 for every applicable namespace."
```

`liquid-spec init` writes the detailed operating manual into `AGENTS.md` and a
source-echo JSON-RPC v2 demo into `adapter.ts`:

```bash
# After setting adapters.candidate.command in liquid-spec.toml:
liquid-spec check --adapter candidate
liquid-spec tools inspect --adapter candidate -n "the_failing_spec"
liquid-spec docs curriculum
liquid-spec docs core-abstractions
liquid-spec check --adapter candidate --json
```

Capabilities are reported by the server. Standard drops use the versioned fixture
catalog; Ruby-only fixture descriptors are tagged `ruby_compat` and are skipped by
servers that do not advertise that capability.

For a human-driven implementation, use exactly the same loop: check, read the first
hint, implement, and check again. `liquid-spec docs json-rpc-protocol-v2` documents the
wire contract.

## Archived Ruby adapter API (legacy gem only)

The material in this section documents the previous Ruby gem and is retained only
for migration. It is not accepted by the Rust binary. The rewrite has one adapter
boundary: an external newline-delimited JSON-RPC v2 process. Ruby comparisons use
`examples/liquid_ruby_jsonrpc_v2.rb` through that same process boundary, so the Rust
runner never loads Liquid in-process and never invokes Ruby callbacks or drops.

The following DSL is retained for users migrating from the Ruby gem. It is not
accepted by the Rust binary; new implementations must expose the JSON-RPC v2
methods documented above.

An adapter is a small Ruby file that tells liquid-spec how to use your implementation:

```ruby
#!/usr/bin/env ruby
require "liquid/spec/cli/adapter_dsl"

# Load your implementation; ctx carries compiled state between callbacks.
LiquidSpec.setup do |ctx|
  require "my_liquid"
end

# Declare what your adapter can't handle (default: check every applicable spec)
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


### JSON-RPC adapters

All adapters use protocol v2 over newline-delimited JSON-RPC. The server implements
`initialize`, `protocol.echo`, `template.compile`, `template.render`,
`template.release`, and the `shutdown` notification. Server diagnostics go to stderr;
stdout must contain only JSON-RPC messages. There are no callbacks or `_rpc_drop`
markers: portable objects use the versioned standard fixture catalog, while Ruby-only
objects are selected by the `ruby_compat` capability. Read
`docs/json-rpc-protocol-v2.md` for the complete contract.

```bash
liquid-spec init
liquid-spec check -- ./my-liquid-server
liquid-spec check --adapter candidate --json > results.json
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

# Called with the artifact bytes and no source recompilation.
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

With both hooks, `liquid-spec bench` validates the dump → load → render roundtrip, reports
raw artifact bytes and steady-state load diagnostics, and measures atomic source
compile + first-render and artifact-load + first-render workflows with 10
interleaved samples in the adapter process. Each sample invokes compile or load
before its first render, but process-level runtime, JIT, and global caches remain
warm. The harness intentionally does not include process startup or IPC.

`liquid-spec bench` warns when either hook is missing because artifact size and
load+first-render results will be omitted. Implementations without a persistent
compiled format may leave the hooks absent; the warning documents that the
benchmark is then limited to source compile and resident render paths.

### Optional: local namespaces

Projects can ship their own spec/benchmark namespaces alongside their adapter:
any `./specs/<name>/` directory in the invoking project is discovered next to the
built-in namespaces and selected with `--namespace <name>` (or `-s <name>`).
Mark benchmark namespaces with `timings: true` in their metadata to make them benchmarkable
with `liquid-spec bench ADAPTER -s <name>`, and `default: false` to keep it
out of regular checks.

## Spec Namespaces

| Namespace | Tests | Description |
|-------|-------|-------------|
| **basics** | 941 | Essential Liquid features - start here! Ordered by complexity with implementation hints |
| **liquid_ruby** | 2,097 | Core Liquid specs from [Shopify/liquid](https://github.com/Shopify/liquid) integration tests |
| **liquid_ruby_lax** | 121 | Lax-mode reference behavior |
| **parser_errors** | 1,905 | Strict parser error compatibility and mutation matrices |
| **partials** | 12 | Include/render focused compatibility specs and timings |
| **benchmarks** | 10 | Storefront, dynamic-partial, `{% liquid %}`, and Shopify-theme performance cases |
| **shopify_production_recordings** | 2,260 | Recorded behavior from Shopify's production Liquid compiler |
| **shopify_theme_dawn** | 26 | Real-world templates from [Shopify Dawn](https://github.com/Shopify/dawn) theme |

### The Basics Namespace

If you're building a new Liquid implementation, **start with the basics namespace**. It runs first and covers all fundamental features from the [official Liquid documentation](https://shopify.github.io/liquid/).

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

### Feature-Based Namespace Selection

Namespaces marked as default are checked unless you select one explicitly with `--namespace` (or `-s`). Advertise only
implemented capabilities from the adapter's JSON-RPC `initialize` response; missing
capabilities cause dependent specs to be skipped:

```json
{"features":["core"],"fixture_sets":{"standard-drops":1}}
```

## Generated Adversarial Coverage

After the recorded ramp passes, optional bounded probes can exercise nearby cases:

```bash
liquid-spec tools mutate --adapter candidate --around=for_loops --limit=100
liquid-spec tools fuzz --adapter candidate --seed=1234 --rounds=500
liquid-spec tools stress --adapter candidate --depth=64 --repetitions=100
```

`mutate` deterministically changes existing specs; `fuzz` produces seeded literal probes;
`stress` generates bounded valid nesting and repetition. These commands stay secondary to
the protocol gate and acceptance ramp. Use `tools eval --compare` for a direct reference
comparison and save any useful discovery as an ordinary YAML spec.

This is differential corpus mutation, not native coverage-guided fuzzing. See
`liquid-spec docs adversarial` for comparison semantics, seed selection, JSON output,
minimization, and how to curate a generated discovery into the permanent corpus.

## CLI Reference

```bash
liquid-spec COMMAND [options]

Core commands:
  liquid-spec [CHECK_OPTIONS]             Follow `default` from liquid-spec.toml
  liquid-spec init [DIRECTORY]            Generate liquid-spec.toml, adapter.ts, and AGENTS.md
  liquid-spec docs [NAME]                 Read implementer documentation
  liquid-spec check [-- ADAPTER_COMMAND]  Check the acceptance ramp
  liquid-spec bench [-- ADAPTER_COMMAND]  Benchmark implementations

Tool collection (`liquid-spec tools help`):
  liquid-spec tools inspect               Inspect matching specs in detail
  liquid-spec tools protocol              Validate adapter protocol conformance
  liquid-spec tools docs                  Print implementation documentation
  liquid-spec tools features              Audit feature tags and scope
  liquid-spec tools report                Analyze benchmark results
  liquid-spec tools check                 Run every verifier
  liquid-spec tools mutate ADAPTER        Deterministic differential mutations
  liquid-spec tools fuzz ADAPTER          Seeded differential fuzz-style testing
  liquid-spec tools stress ADAPTER        Bounded structural stress

Check options:
  -n, --name PATTERN       Only check specs matching PATTERN
  -s, --namespace NAME     Check a spec namespace by directory name
  -c, --compare            Compare output against reference liquid-ruby
  -v, --verbose            Show detailed output
  -l, --list               List available specs
  --list-namespaces        List available spec namespaces
  --list-passed           List specs that passed after the check (ramp/debug audits)
  --spec FILE             Add a standalone YAML spec (repeatable)
  --json                  Output a single JSON summary (for tools)
  --jsonl                 Output one JSON event per line (for benchmark streaming/tools)
  -h, --help               Show help

Examples:
  liquid-spec check --adapter candidate                    # Check all applicable specs
  liquid-spec check --adapter candidate -n for_tag         # Check matching specs
  liquid-spec check --adapter candidate -n assign          # Check matching specs
  liquid-spec check --adapter candidate --compare          # Compare with configured reference
  liquid-spec bench --adapter candidate -n storefront    # Server-side benchmark
  liquid-spec tools check                                # Validate the corpus
  liquid-spec tools features                             # Audit feature scope
  liquid-spec tools inspect --adapter candidate -n "case"
```


### Auditing the Ramp with Dumb Adapters

When changing complexity scores or adding early specs, test the harness with intentionally bad adapters:

- an adapter that returns the template source unchanged
- an adapter that always returns `""`
- an adapter that raises during compile or render

Use `--list-passed` to see accidental passes and `--json` for machine-readable analysis:

```bash
liquid-spec check --adapter candidate --list-passed
liquid-spec check --adapter candidate --json --list-passed > empty-results.json
```

A source-echo adapter should only pass raw-text specs before failing on first object output. An always-empty adapter may pass many empty-output specs, so judge progress by `Complexity level cleared` (or JSON `max_complexity_reached`), not by total passes.

### Matrix Command

The `matrix` command runs specs across multiple adapters simultaneously and shows differences between implementations. This is useful for comparing behavior across different Liquid implementations or configurations.

```bash
liquid-spec tools matrix [options]

Options:
  --all                    Run all default adapters from examples/
  --adapters=LIST          Comma-separated list of adapters
  --reference=NAME         Reference adapter (default: liquid_ruby)
  -n, --name PATTERN       Filter specs by name pattern
  -s, --namespace NAME     Spec namespace to benchmark
  -v, --verbose            Show detailed output

Examples:
  # Compare the default bundled adapters
  liquid-spec tools matrix --all

  # Compare specific adapters
  liquid-spec tools matrix --adapters=liquid_ruby,liquid_ruby_lax

  # Compare adapters on specific tests
  liquid-spec tools matrix --adapters=candidate,liquid-ruby -n truncate
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

Adapters: my_adapter
Output:
  "Hello wo..."
======================================================================
```

### Benchmarking

liquid-spec includes benchmark namespaces for measuring and comparing implementation performance. Benchmarks measure **compile** and **render** times separately, with statistical analysis including mean, standard deviation, and min/max ranges.

#### Single Adapter Benchmarks

Run benchmarks against a single adapter to measure its performance:

```bash
liquid-spec bench --adapter liquid-ruby -n leaderboard
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
all adapters are JSON-RPC processes, so server-owned timings remain comparable and
transport overhead is kept outside compile/render measurements.

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

The benchmark namespace currently includes 10 realistic templates:

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
| `shopify_theme_full_page` | Shopify-shaped Dream theme layout using portable Liquid |
| `shopify_theme_product_page` | Shopify-shaped Dream product page using portable Liquid |

Selecting these specs through `liquid-spec check --adapter candidate -n '^bench_'` checks correctness
without collecting timings; use `liquid-spec bench` for performance measurements.

#### Profiling

The Rust runner leaves profiling to the adapter process. Use the adapter language's
profiler around `benchmark.run`; the protocol keeps compile and render timing separate
and excludes JSON-RPC transport latency from the reported nanoseconds.

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
liquid-spec tools eval --adapter candidate --compare <<EOF
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

✓ PASS (candidate and reference agree)
  "HI"
```

When using `--compare`, both adapters run the supplied expected spec and their
failure sets/messages are compared. Keep `expected` (or `errors`) in the YAML so the
evaluation remains reproducible and language-neutral.

The Rust runner does not write ad-hoc specs automatically; save useful YAML explicitly
and add it with `liquid-spec check --spec FILE`.

## Example Output

Default `check` output is intentionally concise: it shows the lowest-complexity failures
(the next specs to work on) and then one summary line.

Failing check:

```
$ liquid-spec check --adapter candidate

Next best specs to work on:

1) [c=5] object_string_literal
   Template:   "{{ 'world' }}"
   Expected:   "world"
   Got:        "{{ 'world' }}"

   Hint: The {{ }} syntax outputs the value of an expression...

Complexity level cleared: 1 of 5, 2 passes, 1 failures.
```

Successful check (counts depend on selected namespaces/features):

```
$ liquid-spec check --adapter candidate
Complexity level cleared: 1000 of 1000, 1234 passes, 0 failures, 12 skipped.

All checked specs passed.
```

Use `-v` for preamble, per-namespace progress, and skipped-namespace details.

## Example Adapters

See the `examples/` directory:

- **`liquid_ruby_jsonrpc_v2.rb`** - JSON-RPC v2 reference adapter backed by Shopify/liquid

```bash
liquid-spec check --adapter liquid-ruby
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

# Check focused specs against the Shopify/liquid JSON-RPC reference adapter
cargo run -p liquid-spec-cli --bin liquid-spec -- check -- ruby examples/liquid_ruby_jsonrpc_v2.rb

# Regenerate specs from Shopify/liquid source
# (requires ../liquid directory with Shopify/liquid checked out)
bundle exec rake generate
```

### Regenerating Specs

The `rake generate` task:
1. Clones Shopify/liquid at the current version tag
2. Patches its test corpus to capture template/expected pairs
3. Runs the tests and records every `assert_template_result` call
4. Writes captured specs to `specs/liquid_ruby/`

This ensures specs stay synchronized with the reference implementation.

## License

MIT
