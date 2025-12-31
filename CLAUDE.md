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
  config.suite = :liquid_ruby  # :all, :liquid_ruby, :dawn
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
- **`Liquid::Spec::TestGenerator`** - Generates Minitest methods from specs

### Directory Structure

- `bin/` - CLI executable
- `examples/` - Example adapters (liquid_ruby.rb, liquid_ruby_strict.rb, liquid_c.rb)
- `lib/liquid/spec/cli/` - CLI implementation
- `specs/liquid_ruby/` - Core Liquid specs from Shopify/liquid
- `specs/dawn/` - Shopify Dawn theme specs
- `tasks/` - Rake tasks for spec generation
