require "liquid/spec/source"
require "liquid/spec/yaml_source"
require "liquid/spec/text_source"
require "liquid/spec/test_generator"

module Liquid
  module Spec
    NotImplementedError = Class.new(StandardError)

    LIQUID_RUBY_SPECS = File.join(
      __dir__,
      "..",
      "..",
      "specs",
      "liquid_ruby",
      "specs.yml",
    )

    CUSTOM_LIQUID_RUBY_SPECS = File.join(
      __dir__,
      "..",
      "..",
      "specs",
      "liquid_ruby",
      "custom.txt",
    )

    def self.all_sources
      [
        Liquid::Spec::Source.for(Liquid::Spec::LIQUID_RUBY_SPECS),
        Liquid::Spec::Source.for(Liquid::Spec::CUSTOM_LIQUID_RUBY_SPECS),
      ]
    end
  end
end
