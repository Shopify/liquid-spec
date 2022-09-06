module Liquid
  module Spec
    module Adapter
      class LiquidRuby
        def render(spec)
          static_registers = {}
          if filesystem = spec.filesystem
            static_registers[:file_system] = MockFileSystem.new(filesystem)
          end
          context = Liquid::Context.build(
            environments: spec.environment,
            registers: Liquid::Registers.new(static_registers)
          )
          template = Liquid::Template.parse(spec.template, error_mode: spec.error_mode, line_numbers: true)
          template.render(context)
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
