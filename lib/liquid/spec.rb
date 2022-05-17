require_relative "spec/source"
require_relative "spec/yaml_source"
require_relative "spec/test_generator"
require_relative "spec/adapter/liquid_ruby"

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

    def self.all_sources
      [
        Liquid::Spec::Source.for(Liquid::Spec::LIQUID_RUBY_SPECS),
      ]
    end
  end
end
