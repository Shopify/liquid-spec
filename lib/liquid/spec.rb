require "liquid/spec/unit"
require "liquid/spec/source"
require "liquid/spec/yaml_source"
require "liquid/spec/text_source"
require "liquid/spec/liquid_source"
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
      "*{.yml,.txt}"
    )

    DIR_SPECS = File.join(
      __dir__,
      "..",
      "..",
      "specs",
      "**",
      "template.liquid"
    )

    def self.all_sources
      (dir_sources + Dir[SPEC_FILES])
        .reject { |path| File.basename(path) == "environment.yml" }
        .map { |path| Liquid::Spec::Source.for(path) }
    end

    private

    def self.dir_sources
      Dir[DIR_SPECS]
        .map { |path| File.dirname(path, 2) }
        .uniq
    end
  end
end
