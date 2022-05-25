module Liquid
  module Spec
    module Adapter
      class LiquidRuby
        def render(spec)
          if filesystem = spec.filesystem
            Liquid::Template.file_system = MockFileSystem.new(filesystem)
          end
          template = Liquid::Template.parse(spec.template)
          template.render(spec.environment)
        end
      end

      MockFileSystem = Struct.new(:data) do
        def read_template_file(template_path)
          data.fetch(template_path)
        end
      end
    end
  end
end
