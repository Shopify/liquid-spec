# frozen_string_literal: true

module Liquid
  module Spec
    # Generate specs based on calls to SFR's `SectionRendering.render_template`.
    # For sample usage, see:
    # https://github.com/Shopify/storefront-renderer/commit/6607ca14f755f3694f9aca9adb80fddd8d3742ca#diff-1e239d8f850c59af64e019e500a95deb5a461f31b0139259ac9a66cc5d250337
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
