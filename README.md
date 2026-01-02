# liquid-spec

[![CI](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml/badge.svg)](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml)

Test suite for Liquid template implementations. Verify your Liquid implementation produces correct output by running it against 4000+ specs from the reference [Shopify/liquid](https://github.com/Shopify/liquid) implementation.

## Installation

```
gem install liquid-spec
```

## Quick Start

```bash
# Generate an adapter for your implementation
liquid-spec init my_adapter.rb

# Edit my_adapter.rb to implement compile and render for your Liquid implementation

# Run the specs
liquid-spec my_adapter.rb
```

## Writing an Adapter

An adapter tells liquid-spec how to compile and render templates with your implementation:

```ruby
#!/usr/bin/env ruby
require "liquid/spec/cli/adapter_dsl"

LiquidSpec.setup do
  require "my_liquid"  # load your implementation
end

LiquidSpec.configure do |config|
  config.suite = :liquid_ruby  # :all, :liquid_ruby, or :dawn
end

LiquidSpec.compile do |source, options|
  # Parse the template source into your template object
  # options includes :line_numbers, :error_mode, etc.
  MyLiquid::Template.parse(source, **options)
end

LiquidSpec.render do |template, ctx|
  # Render the template with the test context
  # ctx provides:
  #   - ctx.environment    # variables (deep copied)
  #   - ctx.registers      # file_system, template_factory
  #   - ctx.file_system    # for {% include %} and {% render %}
  #   - ctx.error_mode     # :lax or :strict
  #   - ctx.rethrow_errors? # should errors be raised or rendered inline?
  #   - ctx.exception_renderer
  #   - ctx.context_klass  # custom context class if specified
  template.render(ctx.environment)
end
```

## Example Adapters

The `examples/` directory contains ready-to-use adapters:

```bash
# Test Shopify/liquid (pure Ruby)
liquid-spec examples/liquid_ruby.rb

# Test with strict mode
liquid-spec examples/liquid_ruby_strict.rb

# Test with liquid-c extension
liquid-spec examples/liquid_c.rb
```

## CLI Options

```bash
liquid-spec ADAPTER [options]

Options:
  -n, --name PATTERN      Only run specs matching PATTERN
  -s, --suite SUITE       Spec suite: all, liquid_ruby, dawn
  -v, --verbose           Show verbose output
  -l, --list              List available specs
  --max-failures N        Stop after N failures (default: 10)
  --no-max-failures       Run all specs
  -h, --help              Show help

Examples:
  liquid-spec my_adapter.rb                    # run all specs
  liquid-spec my_adapter.rb -n assign          # run specs matching 'assign'
  liquid-spec my_adapter.rb -s liquid_ruby     # run only liquid_ruby suite
  liquid-spec my_adapter.rb -v                 # verbose output
  liquid-spec my_adapter.rb --no-max-failures  # don't stop early
```

## Spec Suites

- **liquid_ruby** - Core Liquid language specs (~4000 tests)
- **dawn** - Shopify Dawn theme section rendering specs
- **all** - Everything

## Development

```bash
# Clone the repo
git clone https://github.com/Shopify/liquid-spec.git
cd liquid-spec

# Run specs against local liquid
ruby -I../liquid/lib -Ilib bin/liquid-spec examples/liquid_ruby.rb

# Generate specs from Shopify/liquid
bundle exec rake generate
```

## License

MIT
