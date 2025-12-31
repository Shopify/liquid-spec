# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

liquid-spec is a test suite for the Liquid templating language. It captures test cases from the reference Shopify/liquid implementation and can verify that other Liquid implementations produce identical output.

## Common Commands

```bash
# Run interpreted tests (standard)
ruby -W:no-experimental -Ilib -Itest test/liquid_ruby_test.rb

# Run compiled template tests (requires Ruby 4.0+ with Box)
RUBY_BOX=1 ruby -W:no-experimental -I../liquid/lib -Ilib -Itest test/liquid_ruby_compiled_test.rb

# Run a specific test by name pattern
RUBY_BOX=1 ruby -W:no-experimental -I../liquid/lib -Ilib -Itest test/liquid_ruby_compiled_test.rb -n '/assign/'

# With bundler (if native extensions compile)
bundle exec rake test           # interpreted
bundle exec rake test_compiled  # compiled

# Generate specs from Shopify/liquid (clones repo to tmp/, runs tests, captures output)
bundle exec rake generate

# Generate only liquid_ruby specs
bundle exec rake generate:liquid_ruby

# Generate only standard_filters specs
bundle exec rake generate:standard_filters
```

## Using Local Liquid Gem

The Gemfile automatically uses a local `../liquid` directory if it exists. This allows testing against a development version of the liquid gem:

```
liquid-spec/
../liquid/     <- local liquid gem (auto-detected)
```

## Architecture

### Spec Generation Flow

1. `rake generate` clones Shopify/liquid to `tmp/liquid/` at the version matching the liquid gem dependency
2. Patches are injected into the cloned repo's test helper to capture test data during execution
3. Tests run in the cloned repo, writing captured specs to `tmp/liquid-ruby-capture.yml`
4. Captured data is formatted and written to `specs/liquid_ruby/*.yml`

### Key Components

- **`Liquid::Spec::Unit`** (`lib/liquid/spec/unit.rb`): Struct representing a single test case with fields: name, expected, template, environment, filesystem, error_mode, etc.

- **`Liquid::Spec::Source`** (`lib/liquid/spec/source.rb`): Factory for loading specs from different formats (YAML, text, directory-based)

- **`Liquid::Spec::TestGenerator`** (`lib/liquid/spec/test_generator.rb`): Dynamically generates test methods on a test class from spec sources. Groups specs by class name prefix (e.g., `AssignTest#test_foo` creates `AssignTest` subclass).

- **`Liquid::Spec::Adapter`** (`lib/liquid/spec/adapter/`): Adapters render templates. `Default` returns expected values; `LiquidRuby` actually renders with the liquid gem. `LiquidRubyCompiled` uses compiled templates.

- **`Liquid::Spec::Assertions`** (`lib/liquid/spec/assertions.rb`): Module factory that provides `assert_parity_for_spec` comparing expected adapter output against actual adapter output.

### Spec File Format (YAML)

```yaml
- name: TestClass#test_description_hash
  template: "{{ foo | upcase }}"
  environment:
    foo: bar
  expected: "BAR"
  error_mode: :lax  # optional
  render_errors: false
  filesystem:       # optional, for include/render tags
    snippet: "content"
```

### Directory Structure

- `specs/liquid_ruby/` - Core Liquid language specs generated from Shopify/liquid tests
- `specs/dawn/` - Shopify Dawn theme section rendering specs
- `lib/liquid/spec/deps/` - Patches applied to Shopify/liquid during spec generation
- `lib/liquid/spec/adapter/` - Adapters for different rendering modes
- `tasks/` - Rake tasks for spec generation

### Testing Compiled Templates

The `LiquidRubyCompiled` adapter in `lib/liquid/spec/adapter/liquid_ruby_compiled.rb` compiles templates to Ruby and runs them in a sandbox. This requires:

1. Ruby 4.0+ with Ruby::Box
2. The `RUBY_BOX=1` environment variable
3. A local liquid gem with compile support at `../liquid`
