require "liquid/spec/unit"
require "liquid/spec/source"
require "liquid/spec/yaml_source"
require "liquid/spec/text_source"
require "liquid/spec/test_generator"

module Liquid
  module Spec
    NotImplementedError = Class.new(StandardError)

    SPEC_FILES = File.join(
      __dir__,
      "..",
      "..",
      "specs",
      "**",
      "*{.yml,.txt,template.liquid}"
    )

    def self.all_sources
      Dir[SPEC_FILES].map do |path|
        Liquid::Spec::Source.for(path)
      end
    end
  end
end
