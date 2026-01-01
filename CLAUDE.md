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

## Writing an Adapter

An adapter defines how your Liquid implementation compiles and renders templates:

```ruby
#!/usr/bin/env ruby
require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "my_liquid"
end

LiquidSpec.configure do |config|
  config.suite = :liquid_ruby  # :all, :liquid_ruby, :shopify_theme_dawn
  config.features = [
    :core,                  # Basic Liquid parsing/rendering
  ]
end

LiquidSpec.compile do |source, options|
  MyLiquid::Template.parse(source, **options)
end

LiquidSpec.render do |template, ctx|
  # ctx provides: assigns, environment, registers, file_system,
  #               exception_renderer, template_factory
  template.render(ctx.variables)
end
```

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

Specs can include an optional `hint` field that provides contextual information about why a spec might fail. Hints are displayed in yellow when the spec fails, helping implementers understand potential causes.

```yaml
- name: blank_with_activesupport
  template: "{% if foo.blank? %}empty{% endif %}"
  expected: "empty"
  environment:
    foo: ""
  hint: "This spec tests blank? which requires ActiveSupport to be loaded"
```

Use hints to communicate:
- Dependencies that must be loaded (e.g., ActiveSupport)
- Implementation-specific behaviors being tested
- Known edge cases or platform differences
- Any context that helps diagnose failures

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

# Default options applied to all specs (can be overridden per-file or per-spec)
defaults:
  render_errors: false
```

### Available Suites

- **`liquid_ruby`** (default: true) - Core Liquid specs from Shopify/liquid integration tests
- **`shopify_production_recordings`** (default: false) - Specs recorded from Shopify production
- **`shopify_theme_dawn`** (default: false) - Real-world theme specs, requires Shopify-specific tags/objects/filters

### Features

Adapters declare which features they support. Suites require specific features to run:

```ruby
LiquidSpec.configure do |config|
  config.features = [:core, :shopify_tags]
end
```

Common features:
- `:core` - Basic Liquid parsing and rendering
- `:shopify_tags` - Shopify-specific tags (schema, style, section)
- `:shopify_objects` - Shopify-specific objects (section, block)
- `:shopify_filters` - Shopify-specific filters (asset_url, image_url)
