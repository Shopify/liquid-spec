# liquid-spec

> Rust CLI and acceptance corpus for Liquid. Every engine is driven through the
> JSON-RPC v2 adapter protocol as an external process. Build with
> `cargo build -p liquid-spec-cli --bin liquid-spec` and run
> `target/debug/liquid-spec` from a checkout (or `make install` for a system
> install that also ships the corpus).

The CLI keeps the acceptance curriculum and the familiar `init`, `docs`,
`check`, `bench`, and `tools` commands. `run` remains a compatibility alias for
`check`. `liquid-spec init` creates a `liquid-spec.toml` adapter manifest, an
executable `adapter.ts` protocol demo, and `AGENTS.md`. Adapters are launched as
external newline-delimited JSON-RPC v2 processes. `--compare` uses a separately
configured reference adapter when reference behavior is needed.

[![CI](https://github.com/Shopify/liquid-spec/actions/workflows/rust.yml/badge.svg)](https://github.com/Shopify/liquid-spec/actions/workflows/rust.yml)

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

```bash
make install
```

This does two things:

1. Builds the release binary and installs `liquid-spec` into Cargo's user bin
   directory (`~/.cargo/bin` by default, or `$CARGO_HOME/bin` when `CARGO_HOME`
   is set).
2. Copies the YAML corpus to
   `$XDG_DATA_HOME/liquid-spec/specs` (defaulting to
   `~/.local/share/liquid-spec/specs` when `XDG_DATA_HOME` is unset).

Without the data directory step, a bare `cargo install` produces a binary that
cannot find any specs. Prefer `make install`, or set `LIQUID_SPEC_ROOT` to a
checkout's `specs/` directory.

Lookup order for the corpus:

1. `LIQUID_SPEC_ROOT` (must be a directory)
2. `./specs` relative to the current working directory
3. `specs/` next to the installed binary
4. `$XDG_DATA_HOME/liquid-spec/specs` or `~/.local/share/liquid-spec/specs`
5. `~/Library/Application Support/liquid-spec/specs` (macOS)
6. `/usr/local/share/liquid-spec/specs` and `/usr/share/liquid-spec/specs`
7. Checkout path via `CARGO_MANIFEST_DIR` (debug builds only)
development, set `LIQUID_SPEC_DOCS` to preview doc edits without rebuilding.

Local-only builds:

```bash
cargo build --release -p liquid-spec-cli --bin liquid-spec
# uses the checkout's specs/ automatically when run from the repo
```

## Quick Start

```bash
# Creates liquid-spec.toml, adapter.ts, and AGENTS.md.
liquid-spec init

# With no subcommand, the manifest's `default = "check"` action runs the
# generated candidate adapter. Check options can be supplied directly too.
liquid-spec
liquid-spec -n assign

# Every implementation is an external JSON-RPC v2 process.
# Start with the curriculum before choosing a focused guide.
liquid-spec docs curriculum
liquid-spec check -- ./my-liquid-server

# Or name a repeatable command from liquid-spec.toml.
liquid-spec check --adapter candidate
liquid-spec tools protocol --adapter candidate
liquid-spec bench --adapter candidate
```

The runner performs the v2 protocol gate before loading Liquid specs. `check` evaluates
the full selected corpus, and the first lowest-complexity failure is the next
implementation lesson. A semantic spec failure exits nonzero after the protocol gate,
so CI can enforce correctness; protocol or adapter-process failures also exit nonzero.
Each check overwrites a deterministically named report under the system temp path,
containing all passes and failures; human output points to it with `[all failures in ...]`.
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
# Start here: the curriculum explains the implementation loop and guide order.
liquid-spec docs curriculum
liquid-spec docs core-abstractions
# Topic names, filenames, and descriptions accept case-insensitive substrings.
liquid-spec docs "pars"
liquid-spec check --adapter candidate --json
```

Capabilities are reported by the server. Standard drops use the versioned fixture
catalog; Ruby-only fixture descriptors are tagged `ruby_compat` and are skipped by
servers that do not advertise that capability.

For a human-driven implementation, use exactly the same loop: check, read the first
hint, implement, and check again. `liquid-spec docs list` prints the absolute docs
directory and every bundled topic path (`.md`). `liquid-spec docs protocol` documents
the wire contract; a case-insensitive substring such as `liquid-spec docs "pars"`
also resolves a unique matching guide.

## Adapter protocol

There is one adapter boundary: an external newline-delimited JSON-RPC v2
process. The server implements `initialize`, `protocol.echo`,
`template.compile`, `template.render`, `template.release`, and the `shutdown`
notification. Server diagnostics go to stderr; stdout must contain only
JSON-RPC messages. Portable objects use the versioned standard fixture catalog;
Ruby-only fixtures are selected by the `ruby_compat` capability. Read
`docs/json-rpc-protocol-v2.md` (or `liquid-spec docs protocol`) for the complete
contract.

```bash
liquid-spec init
liquid-spec check -- ./my-liquid-server
liquid-spec check --adapter candidate --json > results.json
```

### Optional: local namespaces

Projects can ship their own spec/benchmark namespaces alongside their adapter:
any `./specs/<name>/` directory in the invoking project is discovered next to the
built-in namespaces and selected with `--namespace <name>` (or `-s <name>`).
Mark benchmark namespaces with `timings: true` in their metadata to make them
benchmarkable with `liquid-spec bench -s <name>`, and `default: false` to keep
them out of regular checks.

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
  liquid-spec docs [TOPIC]               Read implementer documentation (substring matching)
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

The `matrix` command runs selected specs across multiple configured adapters and
shows observable differences between implementations.

```bash
# Compare every adapter in liquid-spec.toml
liquid-spec tools matrix --all

# Compare named adapters on a focused namespace/spec
liquid-spec tools matrix --adapter candidate --adapter liquid-ruby \
  -s basics -n truncate
```

Adapters are configured in `liquid-spec.toml`; the bundled `liquid-ruby`
reference can be selected by adding it to the manifest or by using
`reference_adapter` with `check --compare`. Matrix output includes per-spec
results and writes the full report to a deterministic temporary path.

Output shows which adapters produce different results for each spec. The full
observed output/error values are also written to a deterministic temporary
report (`[all matrix differences in ...]`); `--json` includes each adapter's
per-spec `results` and the same `report_path`.

### Benchmarking

Benchmark namespaces measure adapter-owned compile and render batches separately.
A server that supports benchmarking advertises `benchmark: true` during
`initialize`.

```bash
liquid-spec bench --adapter candidate -s benchmarks -n bench_dynamic_partials \
  --iterations 100
```

The benchmark command keeps transport overhead outside the server-owned timing
and reports compile/render results. The bundled reference adapter is also
benchmarkable:

```bash
liquid-spec bench --adapter liquid-ruby -s benchmarks
```

The benchmark namespace contains realistic storefront, dynamic-partial,
`{% liquid %}`, and Shopify-shaped templates. See `specs/benchmarks/` for the
current corpus.

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

## Reference adapter

The package ships `examples/liquid_ruby_jsonrpc_v2.rb` — a self-contained
Shopify/liquid JSON-RPC v2 server that uses `bundler/inline` (no Gemfile).
`liquid-spec init` wires it as `reference_adapter = "liquid-ruby"` with the
portable path token `@liquid-spec/examples/liquid_ruby_jsonrpc_v2.rb`, which
resolves against the installed data package or the source checkout.

```bash
# Compare your candidate against Shopify/liquid
liquid-spec check --adapter candidate --compare
liquid-spec tools eval --compare -- ./adapter.ts <<'EOF'
name: smoke
template: "{{ 'hi' | upcase }}"
expected: "HI"
EOF
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

Specs without `error_mode` run once in the adapter's highest supported parse mode
(`strict2`, then `strict`, then `lax`). For an explicit mode array, the highest
supported strict mode is sufficient; an explicitly declared `lax` mode adds a
separate compatibility run. This avoids duplicate strict/strict2 executions while
still testing lax behavior independently.

## Development

```bash
git clone https://github.com/Shopify/liquid-spec.git
cd liquid-spec

# Unit + integration tests for the Rust crates
cargo test --workspace --locked

# Load every built-in namespace (corpus integrity check)
cargo run -p liquid-spec-cli --locked -- tools check

# Focused protocol gate against the built-in test server
cargo run -p liquid-spec-cli --locked -- protocol -- \
  target/debug/liquid-spec-test-server

# Install binary + corpus for use outside the checkout
make install
```

Corpus YAML lives under `specs/`. Implementer guides live under `docs/` and are
embedded into the CLI at build time.

## License

MIT
