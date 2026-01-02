# frozen_string_literal: true

require "liquid/spec/unit"
require "liquid/spec/source"
require "liquid/spec/yaml_source"
require "liquid/spec/text_source"
require "liquid/spec/liquid_source"
require "liquid/spec/suite"
require "liquid/spec/test_generator"
require "liquid/spec/environment_dumper"
require "liquid/spec/section_rendering_spec_generator"
require "liquid/spec/test_drops"
require "liquid/spec/yaml_initializer"
require "liquid/spec/test_filters"
require "liquid/spec/cli/adapter_dsl"

module Liquid
  module Spec
    NotImplementedError = Class.new(StandardError)

    # Legacy: SPEC_FILES glob for backward compatibility
    SPEC_FILES = File.join(
      __dir__,
      "..",
      "..",
      "specs",
      "**",
      "*{.yml,.txt}",
    )

    DIR_SPECS = File.join(
      __dir__,
      "..",
      "..",
      "specs",
      "**",
      "template.liquid",
    )

    # Legacy: all_sources for backward compatibility
    # Prefer using Suite.all for new code
    def self.all_sources
      Dir[SPEC_FILES]
        .reject { |path| File.basename(path) == "environment.yml" }
        .reject { |path| File.basename(path) == "suite.yml" }
        .map { |path| Liquid::Spec::Source.for(path) }
    end

    def self.dir_sources
      Dir[DIR_SPECS]
        .map { |path| File.dirname(path, 2) }
        .uniq
    end
  end
end
