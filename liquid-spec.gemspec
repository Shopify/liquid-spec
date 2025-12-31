# frozen_string_literal: true

require_relative "lib/liquid/spec/version"

Gem::Specification.new do |spec|
  spec.name = "liquid-spec"
  spec.version = Liquid::Spec::VERSION
  spec.authors = ["derekstride"]
  spec.email = ["derek.stride@shopify.com"]

  spec.summary = "Test suite and CLI for testing Liquid template implementations"
  spec.description = "liquid-spec is a test suite for the Liquid templating language. " \
    "Use it to verify your Liquid implementation produces correct output."
  spec.homepage = "https://github.com/Shopify/liquid-spec"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    %x(git ls-files -z).split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end

  spec.bindir = "bin"
  spec.executables = ["liquid-spec"]

  # No runtime dependencies on liquid - the adapter provides it
  spec.add_dependency("super_diff", "~> 0.12.1")
  spec.add_dependency("timecop")
  spec.add_dependency("tty-box")

  spec.require_paths = ["lib"]
end
