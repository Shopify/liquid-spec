module Liquid
  module Spec
    class Source
      include Enumerable

      YAML_EXT = ".yml"

      class << self
        def for(path)
          if File.extname(path) == YAML_EXT
            Liquid::Spec::YamlSource.new(path)
          else
            raise NotImplementedError, "Runner not implmented for filetype: #{File.extname(path)}"
          end
        end
      end

      def initialize(path)
        @spec_path = path
      end

      def each(&block)
        specs.each(&block)
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
