# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

liquid-spec is a test suite and CLI for testing Liquid template implementations. It captures test cases from the reference Shopify/liquid implementation and can verify that any Liquid implementation produces correct output.

## CLI Usage

```bash
# Install the gem
gem install liquid-spec

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

# Show all failures (default stops at 10)
liquid-spec my_adapter.rb --no-max-failures
```

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
  config.suite = :liquid_ruby  # :all, :liquid_ruby, :shopify_theme_dawn
  config.features = [
    :core,                  # Basic Liquid parsing/rendering
  ]
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
    WART: int | size returns 8 because Ruby's Integer#size returns
    the byte representation size (8 bytes on 64-bit systems), NOT
    the number of digits. This is surprising but matches liquid-ruby.
```

**What makes a good hint:**
- **Actionable** - Tells implementers what code to write or what behavior to implement
- **Explains "why"** - For quirky behavior, explains why Liquid works this way
- **Flags warts** - Marks surprising behavior with "WART:" prefix so implementers know it's intentional
- **Progressive** - For complex features, hints guide through the implementation steps

Use hints to communicate:
- Dependencies that must be loaded (e.g., ActiveSupport)
- Implementation-specific behaviors being tested
- Known edge cases or platform differences (mark with "WART:")
- Step-by-step guidance for implementing the feature
- Why a spec exists and what behavior it validates

### Source-Level Metadata

YAML files can include a `_metadata` section for settings that apply to all specs in the file:

- **`hint`**: A global hint displayed when any spec in this file fails
- **`required_options`**: Options that are automatically applied to all specs (e.g., `error_mode: :lax`)

Spec-level settings override source-level settings. For example, a spec with its own `error_mode` will use that instead of the `required_options.error_mode`.

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

# Default complexity for specs without explicit complexity (see COMPLEXITY.md)
# Specs without complexity default to 1000 unless this is set
minimum_complexity: 1000

# Default options applied to all specs (can be overridden per-file or per-spec)
defaults:
  render_errors: false
```

### Complexity Scoring

Each spec should have a `complexity` field indicating implementation difficulty. Lower scores = simpler features to implement first. Specs without explicit complexity default to 1000 or the suite's `minimum_complexity`.

| Range | Feature |
|-------|---------|
| 10-20 | Literals, raw text output |
| 30-50 | Variables, filters, assign |
| 55-60 | Whitespace control, if/else/unless |
| 70-80 | For loops, operators, filter chains |
| 85-100 | Math filters, forloop object, capture, case/when |
| 105-130 | String filters, increment, comment, raw, echo, liquid tag |
| 140-180 | Array filters, property access, truthy/falsy, cycle, tablerow |
| 190-220 | Advanced: offset:continue, parentloop, partials |
| 300-500 | Edge cases, deprecated features |
| 1000+ | Production recordings, unscored specs (default) |

See [COMPLEXITY.md](COMPLEXITY.md) for the full guide with examples.
See [SPECS.md](SPECS.md) for guidelines on writing effective specs.

### Available Suites

- **`liquid_ruby`** (default: true) - Core Liquid specs from Shopify/liquid integration tests
- **`shopify_production_recordings`** (default: false) - Specs recorded from Shopify production
- **`shopify_theme_dawn`** (default: false) - Real-world theme specs, requires Shopify-specific tags/objects/filters

### Features

Adapters declare which features they support. Suites and individual specs can require specific features:

```ruby
LiquidSpec.configure do |config|
  config.features = [:core, :shopify_tags]
end
```

### Available Features

The `:core` feature is the recommended target for most implementations. It's an alias that automatically expands to include other essential features:

```ruby
# From lib/liquid/spec/cli/adapter_dsl.rb
FEATURE_EXPANSIONS = {
  core: [:runtime_drops, :inline_errors],
}
```

**Core features (most implementations should declare `:core`):**
- `:core` - Full Liquid implementation. Expands to include `:runtime_drops` and `:inline_errors`
- `:runtime_drops` - Supports bidirectional communication for drop callbacks (test harness invokes adapter to access drop properties)
- `:inline_errors` - Errors are rendered inline in output rather than raised as exceptions
- `:strict_parsing` - Supports error_mode: :strict (default for most implementations)

**Optional features:**
- `:lax_parsing` - Supports error_mode: :lax for lenient parsing
- `:ruby_types` - Supports Ruby-specific types in environment (Integer, Float, Range, etc.)

**Shopify-specific features:**
- `:shopify_tags` - Shopify-specific tags (schema, style, section)
- `:shopify_objects` - Shopify-specific objects (section, block)
- `:shopify_filters` - Shopify-specific filters (asset_url, image_url)

**JSON-RPC adapters** that can't support bidirectional communication for runtime drops should declare `features = []` to opt out of `:core` and `:runtime_drops`. They will still run all specs except those requiring `:runtime_drops`.

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
complexity: 75
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
complexity: 75                       # Recommended: see COMPLEXITY.md
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
   bd sync
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
