# frozen_string_literal: true

module Liquid
  module Spec
    class Source
      include Enumerable

      YAML_EXT = ".yml"
      TEXT_EXT = ".txt"

      # The Suite this source belongs to (set by Suite when loading)
      attr_accessor :suite

      class << self
        def for(path)
          if File.extname(path) == YAML_EXT
            Liquid::Spec::YamlSource.new(path)
          elsif File.extname(path) == TEXT_EXT
            Liquid::Spec::TextSource.new(path)
          elsif File.directory?(path)
            Liquid::Spec::LiquidSource.new(path)
          else
            raise NotImplementedError, "Runner not implmented for filetype: #{File.extname(path)}"
          end
        end
      end

      def initialize(path)
        @spec_path = path
        @suite = nil
      end

      def each(&block)
        specs.each(&block)
      end

      # Global hint for all specs in this source (from file-level _metadata)
      # Falls back to suite hint if not set
      def hint
        nil
      end

      # Effective hint: source-level hint, or suite-level hint as fallback
      def effective_hint
        hint || suite&.hint
      end

      # Required options that must be supported by the adapter (from file-level _metadata)
      # e.g., { error_mode: :lax }
      def required_options
        {}
      end

      # Effective defaults: suite defaults merged with source required_options
      # Source-level options take precedence over suite defaults
      def effective_defaults
        suite_defaults = suite&.defaults || {}
        suite_defaults.merge(required_options)
      end

      private

      attr_reader :spec_path

      def spec_data
        @spec_data ||= File.read(spec_path)
      end

      def specs
        raise NotImplmentedError, "#{self.class.name} does not implement parsing for specs"
      end
    end
  end
end
