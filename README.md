# liquid-spec

[![CI](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml/badge.svg)](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml)

A conformance test suite for [Liquid](https://github.com/Shopify/liquid) template implementations. Run **4,600+ test cases** extracted from Shopify's reference implementation to verify your Liquid parser/renderer produces correct output.

## Why liquid-spec?

Building a Liquid implementation (compiler, interpreter, or transpiler)? liquid-spec helps you:

- **Verify correctness** against the reference Shopify/liquid behavior
- **Catch regressions** when optimizing or refactoring
- **Discover edge cases** you might not have considered
- **Track compatibility** with specific Liquid versions

## How It Works

```
┌──────────────────────────────────────────────────────────────────────────┐
│                             liquid-spec                                  │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────────┐    │
│  │  YAML Spec  │     │   Adapter   │     │   Your Implementation   │    │
│  │    Files    │────▶│   (Bridge)  │────▶│   (compile + render)    │    │
│  │             │     │             │     │                         │    │
│  │ • template  │     │ LiquidSpec  │     │  MyLiquid.parse(src)    │    │
│  │ • env vars  │     │   .compile  │     │  template.render(vars)  │    │
│  │ • expected  │     │   .render   │     │                         │    │
│  └─────────────┘     └─────────────┘     └─────────────────────────┘    │
│         │                   │                        │                  │
│         └───────────────────┼────────────────────────┘                  │
│                             ▼                                           │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                        Test Runner                                │  │
│  │                                                                   │  │
│  │  For each spec:                                                   │  │
│  │    1. Compile template via adapter                                │  │
│  │    2. Render with environment variables                           │  │
│  │    3. Compare output to expected                                  │  │
│  │    4. Report pass/fail                                            │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Installation

```bash
gem install specific_install
gem specific_install https://github.com/Shopify/liquid-spec
```

## Quick Start

```bash
# 1. Generate an adapter template
liquid-spec init my_adapter.rb

# 2. Edit my_adapter.rb to wire up your implementation (see below)

# 3. Run the specs
liquid-spec my_adapter.rb
```

## Writing an Adapter

An adapter is a small Ruby file that tells liquid-spec how to use your implementation:

```ruby
#!/usr/bin/env ruby
require "liquid/spec/cli/adapter_dsl"

# Load your implementation
LiquidSpec.setup do
  require "my_liquid"
end

# Declare which features you support
LiquidSpec.configure do |config|
  config.features = [:core]  # enables liquid_ruby suite
  # Add :shopify_tags, :shopify_objects, :shopify_filters for Shopify themes
end

# Parse template source into a template object
LiquidSpec.compile do |source, options|
  # options includes: :line_numbers, :error_mode
  MyLiquid::Template.parse(source, **options)
end

# Render a compiled template
LiquidSpec.render do |template, assigns, options|
  # assigns = variables hash
  # options includes: :registers, :strict_errors, :exception_renderer
  template.render(assigns, **options)
end
```

The `options` hash in render includes:
- `:registers` - Hash with `:file_system` and `:template_factory`
- `:strict_errors` - If true, raise errors; if false, render them inline
- `:exception_renderer` - Custom exception handler (optional)

## Test Suites

| Suite | Tests | Description |
|-------|-------|-------------|
| **basics** | 183 | Essential Liquid features - start here! Ordered by complexity with implementation hints |
| **liquid_ruby** | ~1,700 | Core Liquid specs from [Shopify/liquid](https://github.com/Shopify/liquid) integration tests |
| **shopify_production_recordings** | ~3,000 | Recorded behavior from Shopify's production Liquid compiler |
| **shopify_theme_dawn** | 26 | Real-world templates from [Shopify Dawn](https://github.com/Shopify/dawn) theme |

### The Basics Suite

If you're building a new Liquid implementation, **start with the basics suite**. It runs first and covers all fundamental features from the [official Liquid documentation](https://shopify.github.io/liquid/).

Specs are ordered by complexity so you can implement features progressively:

| Complexity | Features |
|------------|----------|
| 10-20 | Raw text output, string/number/boolean literals |
| 30-40 | Variables, basic filters (upcase, size, default) |
| 50-60 | Assign tag, simple if/else conditionals |
| 70-80 | For loops, filter chains, comparison operators |
| 85-90 | Math filters, forloop object, capture tag |
| 100-110 | Case/when, elsif, string manipulation filters |
| 115-130 | Increment/decrement, comments, echo, liquid tag |
| 140-150 | Array filters, property access (dot/bracket notation) |
| 170-180 | Truthy/falsy edge cases, cycle, tablerow |

Each spec includes a detailed `hint` explaining how the feature should be implemented.

### Feature-Based Suite Selection

Suites run based on feature declarations:

```ruby
LiquidSpec.configure do |config|
  # Just core Liquid (liquid_ruby + shopify_production_recordings)
  config.features = [:core]
  
  # Full Shopify theme support (adds shopify_theme_dawn)
  config.features = [:core, :shopify_tags, :shopify_objects, :shopify_filters]
end
```

## CLI Reference

```bash
liquid-spec [command] [options]

Commands:
  liquid-spec run ADAPTER          Run specs with adapter
  liquid-spec matrix               Compare multiple adapters side-by-side
  liquid-spec test                 Run specs against all bundled example adapters
  liquid-spec eval ADAPTER         Quick test a template (YAML via stdin)
  liquid-spec inspect ADAPTER      Inspect specific specs (use with -n)
  liquid-spec init [FILE]          Generate adapter template

Run Options:
  -n, --name PATTERN       Only run specs matching PATTERN
  -s, --suite SUITE        Run specific suite (liquid_ruby, benchmarks, etc.)
  -b, --bench              Run timing suites as benchmarks (measure compile/render times)
  --profile                Profile with StackProf (use with --bench), outputs to /tmp/
  -c, --compare            Compare output against reference liquid-ruby
  -v, --verbose            Show detailed output
  -l, --list               List available specs
  --list-suites            List available test suites
  --max-failures N         Stop after N failures (default: 10)
  --no-max-failures        Run all specs without stopping
  -h, --help               Show help

Examples:
  liquid-spec run my_adapter.rb                    # Run all applicable specs
  liquid-spec run my_adapter.rb -n for_tag         # Run specs matching 'for_tag'
  liquid-spec run my_adapter.rb -s liquid_ruby     # Run only liquid_ruby suite
  liquid-spec run my_adapter.rb --compare          # Compare against reference
  liquid-spec run my_adapter.rb --no-max-failures  # See all failures
  liquid-spec run my_adapter.rb -s benchmarks --bench  # Run benchmarks
  liquid-spec test                                 # Test all bundled adapters
  liquid-spec inspect my_adapter.rb -n "case"      # Debug specific specs
```

### Matrix Command

The `matrix` command runs specs across multiple adapters simultaneously and shows differences between implementations. This is useful for comparing behavior across different Liquid implementations or configurations.

```bash
liquid-spec matrix [options]

Options:
  --all                    Run all available adapters from examples/
  --adapters=LIST          Comma-separated list of adapters
  --reference=NAME         Reference adapter (default: liquid_ruby)
  -n, --name PATTERN       Filter specs by name pattern
  -s, --suite SUITE        Spec suite to run
  -b, --bench              Run timing suites as benchmarks, compare performance
  --profile                Profile with StackProf (use with --bench), outputs to /tmp/
  --max-failures N         Stop after N differences (default: 10)
  --no-max-failures        Show all differences
  -v, --verbose            Show detailed output

Examples:
  # Compare all bundled adapters
  liquid-spec matrix --all

  # Compare specific adapters
  liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax

  # Compare adapters on specific tests
  liquid-spec matrix --adapters=liquid_ruby,liquid_c -n truncate

  # Benchmark performance across implementations
  liquid-spec matrix --adapters=liquid_ruby,liquid_c -s benchmarks --bench
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
liquid-spec run examples/liquid_ruby.rb -s benchmarks --bench
```

Output:
```
Benchmark: Benchmarks
Duration: 5s per spec

  ✓ bench_product_listing
    Compile: 92.305 µs ± 2.399 µs    (89.906 µs … 94.704 µs)  412 allocs
    Render:  82.574 µs ± 2.437 µs    (80.137 µs … 85.011 µs)  156 allocs
    Total:   174.879 µs    10245 runs, 568 allocs

  ✓ bench_shopping_cart
    Compile: 262.659 µs ± 2.528 µs    1013 allocs
    Render:  144.638 µs ± 1.081 µs    170 allocs
    Total:   407.296 µs    8892 runs, 1183 allocs
```

Benchmarks show allocation counts for each phase, helping identify memory-heavy operations. GC is disabled during timing to reduce measurement jitter.

#### Multi-Adapter Performance Comparison

Compare performance across different implementations using `matrix --bench`:

```bash
liquid-spec matrix --adapters=liquid_ruby,liquid_ruby_lax -s benchmarks --bench
```

Each benchmark runs against all adapters, then a summary shows relative performance and allocation differences:

```
======================================================================
SUMMARY
======================================================================

bench_product_listing
  Compile: liquid_ruby_lax ran
    1.08 ± 0.03 times faster than liquid_ruby
  Compile allocs: liquid_ruby_lax (997)
    +16 allocs for liquid_ruby (1013)
  Render: liquid_ruby_lax ran
    1.01 ± 0.03 times faster than liquid_ruby
  Render allocs: liquid_ruby_lax (169)
    +1 allocs for liquid_ruby (170)

----------------------------------------------------------------------
Overall
  Compile:
    liquid_ruby_lax ran 1.05x faster than liquid_ruby (geometric mean)
  Render:
    liquid_ruby ran 1.00x faster than liquid_ruby_lax (geometric mean)
  Total allocations:
    liquid_ruby_lax: 1166 allocs
    liquid_ruby: 1183 allocs (+17)
```

The "Overall" section shows the geometric mean of ratios across all benchmarks, plus total allocation counts for comparing memory efficiency.

#### Benchmark Specs

The benchmark suite includes 11 realistic templates:

| Benchmark | Description |
|-----------|-------------|
| `bench_product_listing` | E-commerce product grid with variants |
| `bench_navigation_menu` | Nested navigation with dropdowns |
| `bench_data_table` | Dynamic table rendering |
| `bench_comment_thread` | Comment thread with nested replies |
| `bench_multiplication_table` | 12×12 nested loops with forloop object |
| `bench_sorted_list_with_pagination` | Sort, limit/offset, cycle, tablerow |
| `bench_invoice_template` | Invoice with line items, discounts, tax |
| `bench_blog_listing` | Blog posts with pagination, tags |
| `bench_shopping_cart` | Cart with discounts, shipping logic |
| `bench_user_directory` | Team directory grouped by department |
| `bench_email_template` | Email with conditional sections |

Without `--bench`, benchmark specs run as regular tests to verify correctness.

#### Profiling with StackProf

Use `--profile` with `--bench` to generate StackProf profiles for detailed performance analysis:

```bash
# Single adapter profiling
liquid-spec run examples/liquid_ruby.rb -s benchmarks --bench --profile

# Multi-adapter profiling
liquid-spec matrix --adapters=liquid_ruby,liquid_c -s benchmarks --bench --profile
```

Profiles are saved to `/tmp/liquid-spec-profile-{timestamp}/`:

```
StackProf profiles saved to: /tmp/liquid-spec-profile-20260107_145903
  /tmp/liquid-spec-profile-20260107_145903/compile_cpu.dump
  /tmp/liquid-spec-profile-20260107_145903/compile_object.dump
  /tmp/liquid-spec-profile-20260107_145903/render_cpu.dump
  /tmp/liquid-spec-profile-20260107_145903/render_object.dump

View with: stackprof /tmp/liquid-spec-profile-20260107_145903/render_cpu.dump
```

For matrix mode, each adapter gets its own profile files (e.g., `liquid_ruby_render_cpu.dump`, `liquid_c_render_cpu.dump`).

Profile types:
- `*_cpu.dump` - CPU time profiles (where time is spent)
- `*_object.dump` - Object allocation profiles (where allocations happen)

### Quick Testing with `eval`

The `eval` command lets you quickly test individual templates. Specs are passed via YAML on stdin, and results are compared against the reference liquid-ruby implementation by default:

```bash
liquid-spec eval examples/liquid_ruby.rb <<EOF
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

```
$ liquid-spec examples/liquid_ruby.rb

Features: core, lax_parsing

Basics ................................. 183/183 passed
Liquid Ruby ............................ 1683/1683 passed
Liquid Ruby (Lax Mode) ................. 6/6 passed
Shopify Production Recordings .......... 2338/2338 passed
Shopify Theme Dawn ..................... skipped (needs shopify_tags, shopify_objects, shopify_filters)

Total: 4210 passed, 0 failed, 0 errors
```

## Example Adapters

See the `examples/` directory:

- **`liquid_ruby.rb`** - Standard [Shopify/liquid](https://github.com/Shopify/liquid) gem
- **`liquid_ruby_strict.rb`** - Shopify/liquid with strict mode
- **`liquid_c.rb`** - [liquid-c](https://github.com/Shopify/liquid-c) native extension

```bash
liquid-spec examples/liquid_ruby.rb
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
- **complexity** - Optional: ordering hint (lower = simpler, runs first)
- **hint** - Optional: implementation guidance for this feature
- **error_mode** - Optional: `:lax` or `:strict`
- **filesystem** - Optional: mock files for include/render tags

## Development

```bash
# Clone
git clone https://github.com/Shopify/liquid-spec.git
cd liquid-spec

# Run specs against Shopify/liquid gem
bundle install
rake

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
