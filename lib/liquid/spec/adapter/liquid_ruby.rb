module Liquid
  module Spec
    module Adapter
      class LiquidRuby
        def render(spec)
          static_registers = {
            file_system: MemoryFileSystem.new(spec.filesystem),
            template_factory: spec.template_factory,
          }
          context = spec.context_klass.build(
            static_environments: Marshal.load(Marshal.dump(spec.environment),
            registers: Liquid::Registers.new(static_registers),
          )
          template = Liquid::Template.parse(spec.template, error_mode: spec.error_mode, line_numbers: true)
          # context.template_name = "templates/index"
          template.render(context)
        end
      end

      class MemoryFileSystem
        attr_reader :data

        def initialize(data)
          @data = data
        end

        def read_template_file(template_path)
          name = template_path.to_s
          data.find { |name, _| name.casecmp?(template_path) }&.last || begin
            full_name = "snippets/#{name.end_with?(".liquid") ? name : "#{name}.liquid"}"
            raise Liquid::FileSystemError, "Could not find asset #{full_name}"
          end
        end
      end
    end
  end
end
