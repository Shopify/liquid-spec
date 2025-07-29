# frozen_string_literal: true

module Liquid
  module Spec
    class SectionRenderingSpecGenerator
      def initialize(context, write_to:)
        @context = context
        @write_to = write_to
      end

      def write_spec(template:, section_file_path:)
        page_name = @context.request.path == "/" ? "index" : @context.request.path[1..].tr("/", "-")
        section_name = File.basename(section_file_path, ".liquid")

        # TODO: maybe add the section_unique_id if present?
        dir = File.join(@write_to, "#{page_name}-#{section_name}")
        FileUtils.mkdir_p(dir)

        source = @context.registers[:theme_render_context].theme.section_templates[section_name].body

        File.write("#{dir}/template.liquid", source)
        File.write("#{dir}/environment.yml", EnvironmentDumper.new(@context).to_yaml)
        File.write("#{dir}/expected.html", template.render(@context))
      end
    end
  end
end
