# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

liquid-spec is a test suite and CLI for testing Liquid template implementations. It captures test cases from the reference Shopify/liquid implementation and can verify that any Liquid implementation produces correct output.

## CLI Usage

```bash
# Install the gem
gem install liquid-spec

# Generate an adapter template
liquid-spec init my_adapter.rb

# Generate a pre-filled adapter for Shopify/liquid
liquid-spec init my_adapter.rb --liquid-ruby

# Run specs with your adapter
liquid-spec run my_adapter.rb

# Run specific specs by name pattern
liquid-spec run my_adapter.rb -n assign

# Run only liquid_ruby specs
liquid-spec run my_adapter.rb -s liquid_ruby

# Verbose output
liquid-spec run my_adapter.rb -v

# List available specs
liquid-spec run my_adapter.rb -l
```

## Writing an Adapter

An adapter defines how your Liquid implementation compiles and renders templates:

```ruby
# my_adapter.rb
require "my_liquid"

LiquidSpec.configure do |config|
  config.suite = :liquid_ruby  # :all, :liquid_ruby, :dawn
end

LiquidSpec.compile do |source, options|
  MyLiquid::Template.parse(source)
end

LiquidSpec.render do |template, context|
  template.render(context[:assigns])
end
```

## Development Commands

```bash
# Run the existing test suite
ruby -Ilib -Itest test/liquid_ruby_test.rb

# Test the CLI locally
ruby -Ilib bin/liquid-spec help
ruby -Ilib bin/liquid-spec init test.rb
ruby -I../liquid/lib -Ilib bin/liquid-spec run test.rb

# Generate specs from Shopify/liquid
bundle exec rake generate
```

## Using Local Liquid Gem

The Gemfile automatically uses a local `../liquid` directory if it exists:

```
liquid-spec/
../liquid/     <- auto-detected for development
```

## Architecture

### CLI Components

- **`bin/liquid-spec`** - Entry point
- **`lib/liquid/spec/cli.rb`** - Command dispatcher  
- **`lib/liquid/spec/cli/init.rb`** - Generates adapter templates
- **`lib/liquid/spec/cli/runner.rb`** - Runs specs with an adapter
- **`lib/liquid/spec/cli/adapter_dsl.rb`** - DSL for LiquidSpec.compile/render

### Spec Components

- **`Liquid::Spec::Unit`** - Single test case struct
- **`Liquid::Spec::Source`** - Loads specs from YAML/text/directories
- **`Liquid::Spec::TestGenerator`** - Generates Minitest methods from specs
- **`Liquid::Spec::Adapter`** - Adapters for the Minitest-based runner

### Directory Structure

- `bin/` - CLI executable
- `lib/liquid/spec/cli/` - CLI implementation
- `lib/liquid/spec/adapter/` - Adapters for Minitest runner
- `specs/liquid_ruby/` - Core Liquid specs from Shopify/liquid
- `specs/dawn/` - Shopify Dawn theme specs
- `tasks/` - Rake tasks for spec generation
