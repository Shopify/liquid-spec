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
┌─────────────────────────────────────────────────────────────────────────────┐
│                              liquid-spec                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────────────────┐    │
│   │  YAML Spec  │      │   Adapter   │      │  Your Implementation    │    │
│   │   Files     │─────▶│   (Bridge)  │─────▶│  (compile + render)     │    │
│   │             │      │             │      │                         │    │
│   │ • template  │      │ LiquidSpec  │      │  MyLiquid.parse(src)    │    │
│   │ • env vars  │      │   .compile  │      │  template.render(vars)  │    │
│   │ • expected  │      │   .render   │      │                         │    │
│   └─────────────┘      └─────────────┘      └─────────────────────────┘    │
│          │                    │                         │                  │
│          │                    │                         │                  │
│          ▼                    ▼                         ▼                  │
│   ┌─────────────────────────────────────────────────────────────────┐      │
│   │                      Test Runner                                │      │
│   │                                                                 │      │
│   │   For each spec:                                                │      │
│   │     1. Compile template via adapter                             │      │
│   │     2. Render with environment variables                        │      │
│   │     3. Compare output to expected                               │      │
│   │     4. Report pass/fail                                         │      │
│   └─────────────────────────────────────────────────────────────────┘      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
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
  MyLiquid::Template.parse(source, **options)
end

# Render a compiled template with test context
LiquidSpec.render do |template, ctx|
  template.render(ctx.environment)
end
```

The `ctx` object in render provides:
- `ctx.environment` - Variables to render with (Hash)
- `ctx.file_system` - For `{% include %}` and `{% render %}` tags
- `ctx.error_mode` - `:lax` or `:strict`
- `ctx.registers` - Implementation-specific data
- `ctx.rethrow_errors?` - Whether to raise or capture errors

## Test Suites

| Suite | Tests | Description |
|-------|-------|-------------|
| **liquid_ruby** | ~1,700 | Core Liquid specs from [Shopify/liquid](https://github.com/Shopify/liquid) integration tests |
| **shopify_production_recordings** | ~3,000 | Recorded behavior from Shopify's production Liquid compiler |
| **shopify_theme_dawn** | 26 | Real-world templates from [Shopify Dawn](https://github.com/Shopify/dawn) theme |

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
liquid-spec ADAPTER [options]

Commands:
  liquid-spec ADAPTER              Run specs with adapter
  liquid-spec init [FILE]          Generate adapter template
  liquid-spec inspect ADAPTER      Inspect specific specs (use with -n)
  liquid-spec eval ADAPTER         Quick test a template expression

Options:
  -n, --name PATTERN       Only run specs matching PATTERN
  -s, --suite SUITE        Run specific suite (liquid_ruby, shopify_production_recordings, etc.)
  -v, --verbose            Show detailed output
  -l, --list               List available specs
  --list-suites            List available test suites
  --max-failures N         Stop after N failures (default: 10)
  --no-max-failures        Run all specs without stopping
  -h, --help               Show help

Examples:
  liquid-spec my_adapter.rb                    # Run all applicable specs
  liquid-spec my_adapter.rb -n for_tag         # Run specs matching 'for_tag'
  liquid-spec my_adapter.rb -s liquid_ruby     # Run only liquid_ruby suite
  liquid-spec my_adapter.rb --no-max-failures  # See all failures
  liquid-spec inspect my_adapter.rb -n "case"  # Debug specific specs
  liquid-spec eval my_adapter.rb -l "{{ 'hi' | upcase }}"  # Quick test
```

## Example Output

```
$ liquid-spec examples/liquid_ruby.rb

Features: core, lax_parsing

Liquid Ruby ............................ 1683/1683 passed
Liquid Ruby (Lax Mode) ................. 6/6 passed
Shopify Production Recordings .......... 2338/2338 passed
Shopify Theme Dawn ..................... skipped (needs shopify_tags, shopify_objects, shopify_filters)

Total: 4027 passed, 0 failed, 0 errors
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
```

Each spec defines:
- **template** - Liquid source to compile and render
- **environment** - Variables available during rendering
- **expected** - Expected output string
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
