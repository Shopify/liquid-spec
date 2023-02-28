module Liquid
  module Spec
    module Adapter
      class LiquidRuby
        def render(spec)
          static_registers = {
            file_system: MemoryFileSystem.new(spec.filesystem),
            template_factory: StubTemplateFactory.new,
          }
          context = Liquid::Context.build(
            static_environments: spec.environment,
            registers: Liquid::Registers.new(static_registers),
          )
          template = Liquid::Template.parse(spec.template, error_mode: spec.error_mode, line_numbers: true)
          context.template_name = "templates/index"
          template.render(context)
        end
      end

      class StubTemplateFactory
        def for(template_name)
          template = Liquid::Template.new
          template.name = "snippets/" + template_name
          template
        end
      end

      MemoryFileSystem = Struct.new(:data) do
        def read_template_file(template_path)
          name = template_path.to_s
          data.fetch(name) do
            # Report the same error as in storefront-renderer
            # (https://github.com/Shopify/storefront-renderer/blob/9014ee25828c6c5f5e8fec278dd0cd6fd04d803b/app/models/theme.rb#L416)
            full_name = "snippets/#{name.end_with?('.liquid') ? name : "#{name}.liquid"}"
            raise Liquid::FileSystemError, "Could not find asset #{full_name}"
          end
        end
      end
    end
  end
end
