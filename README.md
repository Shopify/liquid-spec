# Liquid::Spec

[![CI](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml/badge.svg)](https://github.com/Shopify/liquid-spec/actions/workflows/ruby.yml)

liquid-spec is a test suite for the Liquid language. You can use this test suite to verify that your liquid
implementation is complete.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "liquid-spec"
```

And then execute:

```
$ bundle
```

Or install it yourself as:

```
$ gem install liquid-spec
```

## Writing Specs

Specs are all defined in the `specs/` directory. `specs/vanilla` contains specs
for the base liquid distribution, and `specs/shopify` contains additional specs
only applicable to the filters and tags added in Shopify storefronts.

Specs can be written in YAML format, or in directory format. Directory format
should only be used for larger "integration"-style specs, such as those at
`specs/vanilla/dawn`.

### Directory Specs

Anywhere under `specs/vanilla` or `specs/shopify`, create a directory
containing:
* `TPL.liquid`: an input liquid template
* `EXP.html`: expected HTML output
* `CTX.yml` _(optional)_: input variables

### YAML Specs

It should be fairly obvious from looking at a few examples of any of the YAML
files under `specs` (other than `**/CTX.yml`); just follow the format.

Each YAML file is an arbitrarily-nested hash of descriptive context, ultimately
containing arrays of specs. Specs contain:

* `TPL`: input liquid template
* `EXP`: expected output
* `CTX` _(optional)_: input variables
* `FSS` _(optional)_: filesystem stub: `{ filename => contents }` hash

For example:

```yaml
Include tag:
  supports dynamically chosen templates:
  - TPL: "{% include template %}"
    EXP: Test321
    CTX: { template: "Test321" }
    FSS: { Test321: "Test321" }
```

In some cases, no `CTX` or `FSS` are necessary. If it doesn't make the line too
unreadable, you can also express these using a single-line compact format. For
example:

```yaml
Capture tag:
  captures content to a named variable:
  - TPL: "{% capture 'var' %}words{% endcapture %}{{var}}"
    EXP: words
```

...can be written as:

```yaml
Capture tag:
  captures content to a named variable:
  - "{% capture 'var' %}words{% endcapture %}{{var}}": words
```

As a rule of thumb, don't use this format if it makes the line much longer than
80 characters.

## Usage

To run the spec you need to implement an Adapter that will implement a `#render(spec)` method. The return value should
be the rendered liquid. The adapter for the [Shopify/liquid](https://github.com/Shopify/liquid) implementation is found
at `Liquid::Spec::Adapter::LiquidRuby`.

The spec tests can be generated with the following code:

```ruby
require "test_helper"
require "liquid/spec/deps/liquid_ruby"

class LiquidSpecTest < MiniTest::Test
end

Liquid::Spec::TestGenerator.generate(
  LiquidSpecTest,
  Liquid::Spec.all_sources,
  Liquid::Spec::Adapter::LiquidRuby.new,
)
```
