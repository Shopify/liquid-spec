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
