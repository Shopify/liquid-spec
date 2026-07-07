# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

liquid-spec is a test suite and CLI for testing Liquid template implementations. Its purpose is to act as a harness for the gradual construction of a full, production-ready Liquid implementation: start with trivial passthrough specs, then progressively add variables, filters, control flow, partials, compatibility quirks, and finally production/theme recordings. It captures test cases from the reference Shopify/liquid implementation and can verify that any Liquid implementation produces correct output.

## CLI Usage

```bash
# Install the gem (from GitHub, not published to rubygems.org)
gem install specific_install
gem specific_install https://github.com/Shopify/liquid-spec

# Run an example adapter
liquid-spec examples/liquid_ruby.rb

# Generate an adapter template
liquid-spec init my_adapter.rb

# Run specs with your adapter
liquid-spec my_adapter.rb

# Filter by test name
liquid-spec my_adapter.rb -n assign

# Run specific suite
liquid-spec my_adapter.rb -s liquid_ruby

# Verbose output
liquid-spec my_adapter.rb -v

# List available specs
liquid-spec my_adapter.rb -l

# List available suites
liquid-spec my_adapter.rb --list-suites
```

### Default runner output

The standard (`liquid-spec adapter.rb`) run prints the lowest-complexity failures — the
"next best specs to work on" (capped at `--max-failures`, default 5) — followed by a
single stats line. Preamble, per-suite progress, and skipped-suite lines are verbose-only
(`-v`):

```
Next best specs to work on:

1) [c=70] ForTagTest#test_iterate_with_each...
   ...

Complexity level cleared: 5 of 1000, 1234 passes, 56 failures, 12 skipped.
```

The level is the highest complexity level present in the run that is below the first
failing level (0 when the first level fails; the max level when nothing fails) — a real
level from the ramp, not an interpolated number. `skipped` is omitted when zero. Gem-owned
file paths in failure locations are shortened to `<gem>/.../<basename>:<line>`.

When every run spec passes (0 failures, level = max), a **Congrats** addendum prints 3
suggested paths forward: implement an optional feature that actually had specs skipped
this run (listed dynamically from the skipped-features set, filtered through
`Features::FEATURE_DOCS` to `:optional`, excluding Ruby-interop `:unnecessary` ones),
run `--bench` for performance, or run a matrix test / contribute back to liquid-spec.


### Spec Quality Gates

Run the spec-quality gate when changing complexity scores, hints, or early-ramp specs:

```bash
ruby -Ilib -I$LIQUID -Itest -e 'require File.expand_path("test/spec_quality_test.rb")'
```

It currently enforces:
- complexity scores must be <= 1000
- every spec with effective complexity <= 220 must have an effective hint
- every spec with complexity <= 220 must have a spec-LEVEL hint (`spec.hint`), not just
  suite/file boilerplate. Existing generated/bulk specs without one are grandfathered in
  `test/spec_hint_baseline.txt`; any NEW spec at c<=220 lacking a spec-level hint fails
  the gate, and stale baseline entries (specs that gained a hint or were removed) also
  fail. After intentionally adding hints, shrink the baseline:

  ```bash
  ruby -Ilib scripts/generate_spec_hint_baseline.rb
  ```

### `rake check` — spec verifiers

`rake check` runs all verifiers in `scripts/verifiers/` in-process. Each
verifier is a standalone Ruby script that prints findings (never modifies
files) and returns 0 on success or non-zero on violations. Verifiers marked
`# advisory: true` in their header are non-blocking — they report known debt
but don't fail the overall check.

```bash
rake check          # run all verifiers
```

You can also run individual verifiers directly:

```bash
ruby -Ilib scripts/verifiers/ruby_type_tags.rb      # Ruby-content + instantiate: drops carry a ruby feature tag + complexity > 100
ruby -Ilib scripts/verifiers/lax_mode_declared.rb   # lax-dependent specs declare error_mode: lax (auto-tags lax_parsing)
ruby -Ilib scripts/verifiers/spec_schema.rb         # spec YAML structure: valid, required fields, known features, complexity range
ruby -Ilib scripts/verifiers/lax_placement.rb       # advisory: lax-only specs should live in the liquid_ruby_lax suite
```

**Blocking verifiers** (must be green before pushing):
- `ruby_type_tags` — specs with Ruby-specific content (Hash#inspect, non-string
  keys, `instantiate:` drops) must declare a ruby feature tag and sit above
  complexity 100.
- `lax_mode_declared` — specs that need lax mode must declare `error_mode: lax`
  (the gem auto-tags `lax_parsing`, so lax-opt-out adapters skip it).
- `spec_schema` — every spec YAML file must be well-formed: valid YAML, correct
  top-level structure, required fields (name, template, expected or errors),
  complexity in 1..1000, features from the known set, valid error_mode.
- `minimum_complexity` — specs with advanced features must sit above the
  beginner ramp: Ruby content (`ruby_types`/`ruby_drops`/`binary_data`) and
`instantiate:` drops ≥ 100; `drops` ≥ 200; `template_factory` and
Shopify-specific features ≥ 200; `render_errors: true` and `error_mode: strict2`
≥ 100.

**Advisory verifiers** (report known debt, don't block push):
- `lax_placement` — lax-only specs belong in `specs/liquid_ruby_lax/`, not
  `specs/liquid_ruby/`. Reports misplaced ones; move them with
  `scripts/move_spec.rb`.

Error-mode policy these enforce:
- A spec that needs lax mode must declare `error_mode: lax` (the gem auto-tags
  it `lax_parsing`, so lax-opt-out adapters skip it). `lax_mode_declared`
  catches any that forgot.
- Lax-only specs belong in `specs/liquid_ruby_lax/`, not `specs/liquid_ruby/`.
  `lax_placement` reports misplaced ones; move them with `scripts/move_spec.rb`.
- Specs exercising a lax-vs-strict2 difference that matters declare
  `error_mode: strict2` (auto-tagged `strict2_parsing`).

When you introduce a new cross-cutting rule, add a verifier script in
`scripts/verifiers/` rather than a one-off check, so the rule stays enforced.
Each verifier defines a module with a `run` class method returning 0 or
non-zero, and ends with `exit ModuleName.run if $PROGRAM_NAME == __FILE__` so
it can run standalone. Mark non-blocking checks with `# advisory: true` in the
header.

### Dumb Adapter Ramp Audits

When changing early complexity scores or adding beginner specs, play dumb and verify the harness still behaves like an implementation curriculum:

```bash
# Source echo adapter: should pass only raw text, then fail on first object output
liquid-spec /tmp/echo_adapter.rb -s basics --max-failures 3 --list-passed

# Always-empty adapter: may pass many empty-output specs accidentally; check max complexity
liquid-spec /tmp/empty_adapter.rb -s basics --json --list-passed > /tmp/empty-results.json

# Always-raise adapters: should fail at complexity 0 with clear Error + Hint output
liquid-spec /tmp/raise_compile_adapter.rb -s basics --max-failures 3
liquid-spec /tmp/raise_render_adapter.rb -s basics --max-failures 3
```

Use `--list-passed` to inspect accidental passes and `--json` for tooling. Prefer `Max complexity reached` / `max_complexity_reached` over raw pass count when judging partial or deliberately naive adapters.

### Result Logging

Each test run appends results to `/tmp/liquid-spec-results.jsonl` with the format:
```json
[run_id, version, source_file, test_name, complexity, "success|fail|error"]
```

- `run_id`: Unique timestamp for this run (e.g., "20260106_124439")
- `version`: liquid-spec version (e.g., "0.9.0")
- `source_file`: Path to the spec YAML file
- `test_name`: Name of the individual spec
- `complexity`: Complexity score (default 1000 if not set)
- `status`: "success", "fail", or "error"

This data can be analyzed later to:
- Identify specs that consistently pass early (suggesting lower complexity)
- Find specs that frequently fail (may need better hints or higher complexity)
- Track implementation progress over time
- Tune complexity scores based on real-world implementation order

## Writing an Adapter

An adapter defines how your Liquid implementation compiles and renders templates:

```ruby
#!/usr/bin/env ruby
require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do |ctx|
  require "my_liquid"
  # ctx is a hash for storing adapter state (environment, file_system, etc.)
  # ctx[:environment] = MyLiquid::Environment.new
end

LiquidSpec.configure do |config|
  config.suite = :liquid_ruby  # :all, :basics, :liquid_ruby, :shopify_theme_dawn

  # Declare what your adapter cannot support yet. Specs requiring these
  # features are skipped so you can build incrementally.
  config.missing_features = [:shopify_tags, :shopify_filters]
end

LiquidSpec.compile do |ctx, source, parse_options|
  ctx[:template] = MyLiquid::Template.parse(source, **parse_options)
end

LiquidSpec.render do |ctx, assigns, render_options|
  # assigns: the environment variables for the template
  # render_options: { registers:, strict_errors:, error_mode: }
  ctx[:template].render(assigns, **render_options)
end
```

The `ctx` hash is passed to all blocks and can store adapter state like custom environments, file systems, or translations. This enables adapters that need isolated Liquid environments with custom tags/filters.

Running the adapter file directly shows usage instructions:
```bash
ruby my_adapter.rb
# => "This is a liquid-spec adapter. Run it with: liquid-spec my_adapter.rb"
```

## Development Commands

```bash
# Run example adapter locally
ruby -I../liquid/lib -Ilib bin/liquid-spec examples/liquid_ruby.rb

# Run with verbose output
ruby -I../liquid/lib -Ilib bin/liquid-spec examples/liquid_ruby.rb -v

# Run specific tests
ruby -I../liquid/lib -Ilib bin/liquid-spec examples/liquid_ruby.rb -n assign

# Test the CLI
ruby -Ilib bin/liquid-spec help
ruby -Ilib bin/liquid-spec init test.rb

# Generate specs from Shopify/liquid
bundle exec rake generate
```

## Architecture

### CLI Components

- **`bin/liquid-spec`** - Entry point
- **`lib/liquid/spec/cli.rb`** - Command dispatcher  
- **`lib/liquid/spec/cli/init.rb`** - Generates adapter templates
- **`lib/liquid/spec/cli/runner.rb`** - Runs specs with an adapter
- **`lib/liquid/spec/cli/adapter_dsl.rb`** - DSL for LiquidSpec.setup/configure/compile/render

### Spec Components

- **`Liquid::Spec::Unit`** - Single test case struct
- **`Liquid::Spec::Source`** - Loads specs from YAML/text/directories
- **`Liquid::Spec::Suite`** - Suite configuration loaded from suite.yml
- **`Liquid::Spec::TestGenerator`** - Generates Minitest methods from specs

### Directory Structure

- `bin/` - CLI executable
- `examples/` - Example adapters (liquid_ruby.rb, liquid_ruby_strict.rb, liquid_c.rb)
- `lib/liquid/spec/cli/` - CLI implementation
- `specs/liquid_ruby/` - Core Liquid specs from Shopify/liquid
- `specs/shopify_production_recordings/` - Recorded specs from Shopify production
- `specs/shopify_theme_dawn/` - Shopify Dawn theme specs
- `tasks/` - Rake tasks for spec generation

## Spec Format

### YAML Structure

YAML spec files support two formats:

**Simple format** (array of specs):
```yaml
---
- name: test_one
  template: "{{ foo }}"
  expected: "bar"
```

**Extended format** (with metadata):
```yaml
---
_metadata:
  hint: "These specs require lax mode"
  required_options:
    error_mode: :lax
specs:
- name: test_one
  template: "{{ foo }}"
  expected: "bar"
```

### Hints

**IMPORTANT:** Hints are critical for helping implementers understand what they need to do to make a spec succeed. Every non-trivial spec should have a hint that explains either:

1. **What to implement** - Concrete steps or logic needed to pass the spec
2. **Why the behavior exists** - The higher-order reason for unexpected or quirky behavior
3. **Common pitfalls** - What implementers typically get wrong

Hints are displayed in yellow when the spec fails, making them the first thing implementers see when debugging.

```yaml
- name: empty_string_is_empty
  template: "{% if x == empty %}empty{% else %}not{% endif %}"
  environment: { x: "" }
  expected: "empty"
  complexity: 100
  hint: |
    Recognize 'empty' as a keyword representing the empty state.
    An empty string "" should equal the 'empty' keyword. Create
    an EmptyLiteral node during parsing. During evaluation, compare
    the variable's value against emptiness: empty strings, empty
    arrays, and empty hashes all equal 'empty'.

- name: int_size_returns_byte_size
  template: "{{ num | size }}"
  environment: { num: 42 }
  expected: "8"
  complexity: 150
  hint: |
    QUIRK: int | size returns 8 because Ruby's Integer#size returns
    the byte representation size (8 bytes on 64-bit systems), NOT
    the number of digits. This is surprising but matches liquid-ruby.
```

**What makes a good hint:**
- **Actionable** - Tells implementers what code to write or what behavior to implement
- **Explains "why"** - For quirky behavior, explains why Liquid works this way
- **Flags quirks** - Marks surprising behavior with "QUIRK:" prefix so implementers know it's intentional
- **Progressive** - For complex features, hints guide through the implementation steps

Use hints to communicate:
- Dependencies that must be loaded (e.g., ActiveSupport)
- Implementation-specific behaviors being tested
- Known edge cases or platform differences (mark with "QUIRK:")
- Step-by-step guidance for implementing the feature
- Why a spec exists and what behavior it validates

### Source-Level Metadata

YAML files can include a `_metadata` section for settings that apply to all specs in the file:

- **`hint`**: A global hint displayed when any spec in this file fails
- **`required_options`**: Options that are automatically applied to all specs (e.g., `error_mode: :lax`)

Spec-level settings override source-level settings. For example, a spec with its own `error_mode` will use that instead of the `required_options.error_mode`.

## Good Specs

Good specs preserve the project goal: help someone build a production-ready Liquid implementation gradually. A spec should teach one behavior at the right time, fail with an actionable message, and point to implementation guidance when the behavior is not obvious.

### Ramp discipline

- First-contact specs for a feature must be tiny, gentle, and hinted. If needed, score the first spec one point lower than follow-up specs so it appears first.
- Keep the 0-50 band boring: passthrough, literals, missing variables, simple variable lookup, a few simple filters, and assign.
- Keep whitespace control (`{{-`, `-}}`, `{%-`, `-%}`), drop/to_liquid boundaries, generated filter matrices, parser recovery, date/time quirks, and filesystem/security quirks out of the beginner band.
- Generated specs should not flood the early ramp. Prefer curated beginner specs early; generated compatibility breadth generally starts at 120+ or much later.
- If a dumb adapter that returns the input, returns `""`, or raises for everything passes a spec unexpectedly, either the spec is too weak or the complexity/hint needs review.
- When judging naive adapters, prefer `Max complexity reached` over total pass count. An always-empty adapter can pass later specs whose correct output is empty, but it should not advance through the contiguous ramp.

### Error specs: prefer raised errors over inline errors

Most specs that exercise an error path should let the error **raise** and
match it with `errors:`. Do **not** set `render_errors: true` (inline error
rendering) unless the spec is specifically testing inline-error *display*
behaviour — and those specs must declare `features: [inline_errors]`.

Two raised-error forms exist:

- `errors: parse_error:` — the template fails to **parse** (syntax errors,
  unknown tags in strict mode, unclosed blocks, …).
- `errors: render_error:` — the template parses but **rendering** raises
  (division by zero, invalid filter arguments, accessing a non-drop object,
  include-inside-render, …).

```yaml
- name: division_by_zero_lax
  template: "{{ 10 | divided_by: 0 }}"
  errors:
    render_error:
      - divided by 0
  complexity: 200
  error_mode: lax
```

```yaml
- name: unknown_tag_strict_parse_error
  template: "{% nonexistent_tag %}content{% endnonexistent_tag %}"
  error_mode: strict
  errors:
    parse_error:
      - Unknown tag
  complexity: 300
```

### Matching error patterns

Each entry under `parse_error:` / `render_error:` is matched against:

1. The full exception message
2. The "core" message (text after the last `): ` or `: `)
3. The exception **class name** (e.g. `NoMethodError`, `Liquid::ArgumentError`)

A **string** pattern is a case-insensitive, literal substring (special
characters are escaped). A **Regexp** pattern (`!ruby/regexp /.../i`) is
used as-is, so metacharacters like `|`, `.+`, and anchors work. **All**
listed patterns must match for the spec to pass. Use multiple patterns to
pin down the error precisely without coupling to exact wording:

```yaml
- name: sec_wide_open_object_name_raises_no_to_liquid
  template: "{{ o.name }}"
  environment:
    o:
      instantiate:WideOpenObject: {}
  errors:
    render_error:
      - NoMethodError        # the error class name
      - to_liquid            # what's missing from the message
  complexity: 220
```

```yaml
- name: error_in_partial_line_3_precise
  template: "{% render 'multiline' %}"
  filesystem:
    multiline.liquid: |
      first line
      second line
      {{ bad | divided_by: 0 }}
  environment:
    bad: 99
  errors:
    render_error:
      - multiline            # partial name appears in the error
      - line 3               # line number within the partial
      - divided by 0         # the underlying error
  complexity: 550
  error_mode: lax
```

A **Regexp** pattern (used as-is, unlike string patterns which are literal
substrings) — useful for alternation without doubling up specs:

```yaml
- name: regexp_render_error_match
  template: "{{ 10 | divided_by: 0 }}"
  errors:
    render_error:
      - !ruby/regexp /ZeroDivision|divided by/i
  complexity: 200
```

**Best practices for error patterns:**

- **Match the error class name** (`NoMethodError`, `Liquid::SyntaxError`, …)
  to assert the *kind* of error, not just its message text.
- **Match one stable substring of the message** that captures the meaningful
  part (e.g. `divided by 0`, `to_liquid`, `Unknown tag`). Avoid matching the
  full message — wording varies across implementations.
- **Match location info when relevant** — partial name and `line N` — but
  keep those as separate patterns so an implementation that lacks one of
  them fails clearly on that specific pattern.
- **Use a Regexp (`!ruby/regexp`)** when you need alternation or anchors
  rather than a literal substring. Note: backslash escapes inside the YAML
  regexp literal must be doubled (write `\\d`, not `\d`), because YAML
  processes the scalar before the regexp is compiled. Prefer backslash-free
  patterns where possible (e.g. `!ruby/regexp /ZeroDivision|divided by/i`).
- **Never set `render_errors: true`** for new specs. New specs should always
  let errors raise and match them with `errors: parse_error:` /
  `errors: render_error:`. The inline form (`render_errors: true` with
  `errors: output:`) is legacy and should not be added to new specs.

## Suite Configuration

Each suite directory contains a `suite.yml` file that configures the suite:

```yaml
---
# Human-readable name
name: "Liquid Ruby"
description: "Core Liquid template engine behavior"

# Whether this suite runs by default (when suite: :all)
default: true

# Context hint displayed when any spec in this suite fails
hint: |
  These specs test core Liquid functionality.
  Failures indicate missing or incorrect Liquid behavior.

# Required features - adapter must declare these to run this suite
required_features:
  - core

# Default complexity for specs without explicit complexity (see `liquid-spec docs complexity`)
# Specs without complexity default to 1000 unless this is set
minimum_complexity: 1000

# Default options applied to all specs (can be overridden per-file or per-spec)
defaults:
  render_errors: false
```

### Complexity Scoring

Each spec should have a `complexity` field indicating implementation difficulty. Lower scores = simpler features to implement first. Specs without explicit complexity default to 1000 or the suite's `minimum_complexity`. Complexity is capped at 1000; do not score specs above 1000.

| Range | Feature |
|-------|---------|
| 0-1 | Foundation: empty template, literal passthrough, whitespace/newline preservation |
| 5-20 | First object output and literal breadth: strings, numbers, booleans, nil-as-empty |
| 30-50 | Variables, missing variables, very simple filters, assign |
| 55-65 | Basic if/else/unless and simple boolean composition |
| 70-100 | Gentle loops, comparisons, forloop basics, capture, simple case/when |
| 105-150 | Common filters/tags: string filters, comment/raw, increment, interrupts, loop modifiers, whitespace control |
| 160-220 | Generated filter breadth, truthy/falsy edge cases, cycle/tablerow, first partials/filesystem, Ruby/reference quirks |
| 230-400 | Long-tail standard behavior: advanced lookup, parser edge cases, scope/filesystem interactions |
| 500-900 | Mature compatibility: parser mutation matrices, resource-limit accounting, recursion/deep nesting, security-sensitive quirks, date/time/Ruby quirks |
| 1000 | Production recordings and unscored specs (default) |

See [`liquid-spec docs complexity`](`liquid-spec docs complexity`) for the full guide with examples.
See [SPECS.md](SPECS.md) for guidelines on writing effective specs.

### Available Suites

- **`liquid_ruby`** (default: true) - Core Liquid specs from Shopify/liquid integration tests
- **`shopify_production_recordings`** (default: false) - Specs recorded from Shopify production
- **`shopify_theme_dawn`** (default: false) - Real-world theme specs, requires Shopify-specific tags/objects/filters

### Features

Adapters declare which features they do **not** support yet. Suites and individual specs can require capabilities; any required capability listed in `missing_features` is skipped so implementations can grow incrementally:

```ruby
LiquidSpec.configure do |config|
  # Empty means "try every spec". Add unsupported capabilities here.
  config.missing_features = [:shopify_tags]
end
```

### Available Features

Feature selection is denylist-based. Leave `missing_features` empty to try everything, or add unsupported capabilities while the implementation is still growing.

**Common features to list in `missing_features`:**
- `:drops` - Adapter cannot support the standard test drop library yet (see docs/test_drops.md)
- `:inline_errors` - Adapter cannot render errors inline yet
- `:lax_parsing` - Adapter does not support `error_mode: :lax`
- `:ruby_types` / `:ruby_drops` / `:binary_data` - Adapter cannot consume Ruby-specific values from specs
- `:template_factory` - Adapter cannot support template factory/artifact callbacks
- `:strict2_blank_body_errors` - Aspirational "NEW STRICT2 CONTRACT" (strict2 surfaces inline errors even for blank block bodies); liquid-ruby 5.13 does not implement this, so opt out until your adapter deliberately adopts it

**Shopify-specific features:**
- `:shopify_tags` - Shopify-specific tags (schema, style, section)
- `:shopify_objects` - Shopify-specific objects (section, block)
- `:shopify_filters` - Shopify-specific filters (asset_url, image_url)
- `:shopify_includes`, `:shopify_blank`, `:shopify_error_handling`, `:shopify_error_format`, `:shopify_string_access` - Shopify platform/theme behavior beyond portable Liquid
- `:shopify_resource_limits` - Shopify render score tracking and cumulative limit enforcement across partials. Implementation plumbing, not Liquid semantics; recursion/stack-depth specs are core.

**JSON-RPC adapters** that can't support the standard test drops yet should set `config.missing_features = [:drops, :ruby_types, :ruby_drops, :binary_data]` (plus any Shopify capabilities they lack).


### JSON-RPC Adapter Setup Notes

JSON-RPC is the main path for non-Ruby Liquid implementations. Keep it especially well documented and tested.

- Generate with `liquid-spec init --jsonrpc my_adapter.rb`.
- The server implements `initialize`, `compile`, `render`, and `quit` over newline-delimited JSON-RPC on stdin/stdout.
- Server logs must go to stderr, never stdout.
- The Ruby adapter controls spec selection with `config.missing_features`; server-reported `features` are informational.
- Minimal JSON-RPC implementations should usually skip Ruby/transport-specific specs: `:drops`, `:ruby_types`, `:ruby_drops`, `:binary_data`, `:template_factory`, plus Shopify-specific features.
- Implement the standard test drops (see docs/test_drops.md) to enable `:drops`. Standard drops use `_instantiate` markers — no RPC callbacks needed.
- Prefer `result.error` for Liquid parse/render errors; legacy JSON-RPC errors `-32000`/`-32001` are accepted for compatibility.
- Render receives `options.strict_errors`; when it is false, render errors should become inline Liquid error output.

Run JSON-RPC checks with:

```bash
ruby -Ilib -I$LIQUID -Itest -e 'require "test_helper"; require File.expand_path("test/json_rpc_test.rb")'
ruby -Ilib -I$LIQUID bin/liquid-spec examples/json_rpc_ruby_liquid.rb -n '^empty_template$|^literal_passthrough$' --json
```

## The Eval Tool

The `liquid-spec eval` command is the primary tool for testing individual templates and discovering behavioral differences. **Always use `--compare`** to validate your implementation against the reference liquid-ruby.

### Why Use Eval?

1. **Quick iteration** - Test a single template without running the full suite
2. **Discover differences** - `--compare` shows exactly where your implementation differs from the reference
3. **Generate specs** - Results are automatically saved to `/tmp/liquid-spec-{date}.yml` for contribution
4. **Debug failures** - Understand why a specific template produces unexpected output

### Basic Usage

```bash
# Quick test with automatic comparison to reference
liquid-spec eval adapter.rb -n test_name --liquid="{{ 'hello' | upcase }}"

# Test with environment variables
liquid-spec eval adapter.rb -n test_var -l "{{ x | size }}" -a '{"x": [1,2,3]}'

# Test with expected output (pass/fail check)
liquid-spec eval adapter.rb -n test_check -l "{{ 5 | plus: 3 }}" -e "8"
```

### Using --compare (Recommended)

The `--compare` flag runs your template against the reference liquid-ruby implementation first, then compares results. This is the best way to find behavioral differences:

```bash
# Compare mode (default for inline templates)
liquid-spec eval adapter.rb -n test_filter --liquid="{{ 'hi' | upcase }}" --compare

# When implementations differ, you'll see:
# ✗ FAIL
# Difference: Reference output "HI" but yours produced "Hi"
```

**When to use --compare:**
- Testing any new feature implementation
- Debugging a failing spec
- Exploring edge cases
- Generating specs for contribution

### YAML Spec Input

For complex tests, use YAML input via stdin or file:

```bash
# From stdin (heredoc) - great for multi-line templates
cat <<EOF | liquid-spec eval adapter.rb --compare
name: test_for_loop_with_break
hint: "break should exit the loop immediately"
complexity: 120
template: |
  {% for i in (1..5) %}
    {% if i == 3 %}{% break %}{% endif %}
    {{ i }}
  {% endfor %}
expected: |
  
    1
  
    2
  
EOF

# From a YAML file
liquid-spec eval adapter.rb --spec=my_test.yml --compare
```

### Spec YAML Format

```yaml
name: test_descriptive_name          # Required: unique identifier
hint: "Explain what this tests"      # Recommended: helps debug failures
complexity: 75                       # Recommended: see `liquid-spec docs complexity`
template: "{{ x | upcase }}"         # Required: the Liquid template
expected: "HELLO"                    # Optional with --compare: auto-filled from reference
environment:                         # Optional: variables available to template
  x: hello
```

### Auto-Save and Contribution

Every eval run saves results to `/tmp/liquid-spec-{date}.yml`. When a difference is detected, you'll see:

```
============================================================
  DIFFERENCE DETECTED
============================================================

This spec reveals a behavioral difference worth documenting.
Please contribute it: https://github.com/Shopify/liquid-spec
```

Review the saved specs and contribute interesting ones to liquid-spec!

### Programmatic API

You can also use eval from Ruby code for automated testing:

```ruby
require 'liquid/spec/cli/adapter_dsl'

# Run a spec and get results
LiquidSpec.evaluate("adapter.rb", <<~YAML, compare: true)
  name: test_upcase_filter
  hint: "upcase should convert to uppercase"
  complexity: 40
  template: "{{ 'hello' | upcase }}"
  expected: "HELLO"
YAML
```

### Tips for Effective Testing

1. **Always name your specs** - Use descriptive names like `test_for_break_in_nested_loop`
2. **Add hints** - Explain what behavior you're testing and why it matters
3. **Set complexity** - Helps organize specs by implementation difficulty
4. **Use --compare first** - Let the reference fill in `expected` before asserting
5. **Test edge cases** - Empty arrays, nil values, unusual inputs
6. **Save interesting failures** - Differences reveal implementation gaps worth documenting

## Filesystem in Specs

Specs that use `{% include %}` or `{% render %}` need a `filesystem:` field. This is always a simple hash mapping filenames to their content:

```yaml
- name: test_render_partial
  template: "{% render 'greeting' %}"
  expected: "Hello!"
  filesystem:
    greeting.liquid: "Hello!"

- name: test_include_with_variable
  template: "{% include 'card' %}"
  expected: "Product: $99"
  environment:
    title: "Product"
    price: 99
  filesystem:
    card.liquid: "{{ title }}: ${{ price }}"
```

The `.liquid` extension is optional - both `greeting` and `greeting.liquid` work as keys.

## Object Instantiation in Specs

Specs can include custom Ruby objects (drops, etc.) in their environment. We use a simple `instantiate:ClassName` format - **no YAML tags like `!ruby/object`**.

### Format

Any string value starting with `instantiate:` triggers object creation:

```yaml
environment:
  # Simple: no arguments
  my_drop: "instantiate:CountingDrop"

  # With arguments: value after the key becomes constructor args
  user:
    instantiate: StringDrop
    value: "hello"

  # Hash arguments passed to constructor
  renderer:
    instantiate: StubExceptionRenderer
    raise_internal_errors: false
```

### How It Works

1. Spec loader detects `instantiate:ClassName` pattern
2. Looks up `ClassName` in `Liquid::Spec::ClassRegistry`
3. Calls `registry[klass].call(remaining_hash)` to create instance
4. If class not found in registry, raises hard error

### ClassRegistry

Classes must be registered before use:

```ruby
# In lib/liquid/spec/deps/liquid_ruby.rb
Liquid::Spec::ClassRegistry.register("CountingDrop") { |p| CountingDrop.new(p) }
Liquid::Spec::ClassRegistry.register("StringDrop") { |p| StringDrop.new(p) }
```

The lambda receives whatever hash/value was alongside `instantiate:` and must return the instance.

### Available Classes

See `lib/liquid/spec/deps/liquid_ruby.rb` for all registered classes:
- `CountingDrop`, `ToSDrop`, `TestDrop` - Test drops
- `StringDrop`, `IntegerDrop`, `BooleanDrop` - Value drops
- `StubExceptionRenderer` - Exception handling
- `StubTemplateFactory` - Template factories
- `SafeBuffer` - HTML-safe strings (requires ActiveSupport)

### Adding New Classes

1. Define the class in `lib/liquid/spec/deps/liquid_ruby.rb` or `lib/liquid/spec/test_drops.rb`
2. Register it: `Liquid::Spec::ClassRegistry.register("MyClass") { |p| MyClass.new(p) }`
3. Use in specs: `my_var: { instantiate: MyClass, arg1: value1 }`

## Editing YAML Specs with yq

If the `yq` tool is available, prefer it for bulk YAML edits. You can write bash scripts that make multiple edits in one go:

```bash
#!/bin/bash
# Bulk update complexity scores in a spec file

FILE="specs/liquid_ruby_lax/variable_type_filters.yml"

# Update metadata minimum_complexity
yq -i '._metadata.minimum_complexity = 500' "$FILE"

# Update all specs with complexity 150 to 500
yq -i '(.specs[] | select(.complexity == 150)).complexity = 500' "$FILE"

# Add 350 to all complexity values under 200
yq -i '(.specs[].complexity | select(. < 200)) += 350' "$FILE"

# Set a value in suite config
yq -i '.minimum_complexity = 500' specs/liquid_ruby_lax/suite.yml
```

Common yq patterns for spec files:

```bash
# Read a value
yq '.specs[0].name' file.yml

# Update matching specs by name
yq -i '(.specs[] | select(.name == "test_foo")).complexity = 100' file.yml

# Add a hint to all specs missing one
yq -i '(.specs[] | select(.hint == null)).hint = "TODO: add hint"' file.yml

# Delete a field from all specs
yq -i 'del(.specs[].some_field)' file.yml

# Count specs
yq '.specs | length' file.yml
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
