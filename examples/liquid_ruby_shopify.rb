#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter with Shopify-specific tags/filters stubbed
#
# This adapter implements the minimal Shopify extensions needed to run
# Dawn theme specs with the standard Liquid gem.
#
# Run: liquid-spec examples/liquid_ruby_shopify.rb
#

require "liquid/spec/cli/adapter_dsl"
require "json"

# Module to extract and apply schema defaults to section data
module SchemaDefaults
  class << self
    # Extract schema JSON from template source
    def extract_schema(source)
      return nil unless source

      match = source.match(/\{%\s*schema\s*%\}(.*?)\{%\s*endschema\s*%\}/m)
      return nil unless match

      JSON.parse(match[1].strip)
    rescue JSON::ParserError
      nil
    end

    # Apply schema defaults to section data
    def apply_defaults(section_data, schema)
      return section_data unless schema

      section_data = (section_data || {}).dup

      # Apply section-level setting defaults
      section_data["settings"] = apply_setting_defaults(
        section_data["settings"] || {},
        schema["settings"] || []
      )

      # Apply block-level setting defaults
      if section_data["blocks"] && schema["blocks"]
        block_schemas = schema["blocks"].to_h { |b| [b["type"], b] }

        section_data["blocks"] = section_data["blocks"].map do |block|
          block = block.dup
          block_schema = block_schemas[block["type"]]
          if block_schema
            block["settings"] = apply_setting_defaults(
              block["settings"] || {},
              block_schema["settings"] || []
            )
          end
          block
        end
      end

      section_data
    end

    private

    def apply_setting_defaults(settings, schema_settings)
      settings = settings.dup
      schema_settings.each do |setting|
        id = setting["id"]
        next unless id
        next if settings.key?(id) && !settings[id].nil? && settings[id] != ""

        settings[id] = setting["default"] if setting.key?("default")
      end
      settings
    end
  end
end

LiquidSpec.setup do
  require "liquid"

  # Disable liquid-c if present
  if defined?(Liquid::C)
    Liquid::C.enabled = false
  end

  # Register Shopify-specific tags

  # {% schema %} - outputs nothing, just stores JSON schema
  class SchemaTag < Liquid::Block
    def render(_context)
      "" # Schema blocks don't output anything
    end
  end
  Liquid::Template.register_tag("schema", SchemaTag)

  # {% style %} - outputs a <style> tag with the content
  class StyleTag < Liquid::Block
    def render(context)
      content = super
      "<style>#{content}</style>"
    end
  end
  Liquid::Template.register_tag("style", StyleTag)

  # {% javascript %} - outputs nothing (deferred to theme JS)
  class JavascriptTag < Liquid::Block
    def render(_context)
      ""
    end
  end
  Liquid::Template.register_tag("javascript", JavascriptTag)

  # {% form %} - outputs a form tag
  class FormTag < Liquid::Block
    def initialize(tag_name, markup, options)
      super
      @form_type = markup.strip.split(/[,\s]/).first&.delete("'\"") || "unknown"
    end

    def render(context)
      content = super
      %(<form method="post" action="/form/#{@form_type}">#{content}</form>)
    end
  end
  Liquid::Template.register_tag("form", FormTag)

  # {% paginate %} - pagination wrapper
  class PaginateTag < Liquid::Block
    def initialize(tag_name, markup, options)
      super
      @markup = markup.strip
    end

    def render(context)
      # Just render the content without actual pagination
      super
    end
  end
  Liquid::Template.register_tag("paginate", PaginateTag)

  # {% section %} - includes a section (stub - just outputs nothing)
  class SectionTag < Liquid::Tag
    def render(_context)
      ""
    end
  end
  Liquid::Template.register_tag("section", SectionTag)

  # {% sections %} - includes multiple sections (stub)
  class SectionsTag < Liquid::Tag
    def render(_context)
      ""
    end
  end
  Liquid::Template.register_tag("sections", SectionsTag)

  # {% layout %} - specifies layout (stub - outputs nothing)
  class LayoutTag < Liquid::Tag
    def render(_context)
      ""
    end
  end
  Liquid::Template.register_tag("layout", LayoutTag)

  # Register Shopify-specific filters
  module ShopifyFilters
    # Translation filter - returns the key or a simple lookup
    def t(input)
      # Return just the last part of the translation key as a simple stub
      # e.g., "sections.header.announcement" -> "Announcement"
      return input unless input.is_a?(String)

      parts = input.split(".")
      parts.last.tr("_-", " ").capitalize
    end

    # Asset URL filters - return the input as-is for testing
    def asset_url(input)
      input.to_s
    end

    def asset_img_url(input, *_args)
      input.to_s
    end

    def image_url(input, *_args)
      return "" if input.nil?

      if input.respond_to?(:src)
        input.src
      elsif input.respond_to?(:[]) && input["src"]
        input["src"]
      else
        input.to_s
      end
    end

    def img_url(input, *_args)
      image_url(input)
    end

    # Shopify CDN filters
    def shopify_asset_url(input)
      input.to_s
    end

    def file_url(input)
      input.to_s
    end

    def file_img_url(input, *_args)
      input.to_s
    end

    # Font filters
    def font_url(input, *_args)
      input.to_s
    end

    def font_face(input, *_args)
      ""
    end

    def font_modify(input, *_args)
      input
    end

    # Color filters
    def color_to_rgb(input)
      input.to_s
    end

    def color_to_hsl(input)
      input.to_s
    end

    def color_modify(input, *_args)
      input.to_s
    end

    def color_brightness(input)
      128 # Return middle brightness
    end

    def brightness_difference(input, _other)
      0
    end

    def color_contrast(input, _other)
      1.0
    end

    # URL filters
    def link_to(input, url, *_args)
      %(<a href="#{url}">#{input}</a>)
    end

    def link_to_tag(tag, *_args)
      tag.to_s
    end

    def link_to_type(type, *_args)
      type.to_s
    end

    def link_to_vendor(vendor, *_args)
      vendor.to_s
    end

    def url_for_type(input, *_args)
      "/collections/types?q=#{input}"
    end

    def url_for_vendor(input, *_args)
      "/collections/vendors?q=#{input}"
    end

    def within(url, _collection)
      url.to_s
    end

    def sort_by(url, sort_option)
      "#{url}?sort_by=#{sort_option}"
    end

    # Payment type image
    def payment_type_img_url(input, *_args)
      input.to_s
    end

    # Money filters
    def money(input)
      return "$0.00" if input.nil?

      cents = input.to_i
      dollars = cents / 100.0
      format("$%.2f", dollars)
    end

    def money_with_currency(input)
      "#{money(input)} USD"
    end

    def money_without_currency(input)
      money(input).delete("$")
    end

    def money_without_trailing_zeros(input)
      money(input).sub(/\.00$/, "")
    end

    # JSON filter
    def json(input)
      require "json"
      JSON.generate(input)
    end

    # Stylesheet/script tag helpers
    def stylesheet_tag(url, *_args)
      %(<link rel="stylesheet" href="#{url}">)
    end

    def script_tag(url, *_args)
      %(<script src="#{url}"></script>)
    end

    # Image tag helper
    def image_tag(input, *_args)
      src = image_url(input)
      %(<img src="#{src}">)
    end

    # Placeholder SVG
    def placeholder_svg_tag(type, *_args)
      %(<svg class="placeholder-svg" data-type="#{type}"></svg>)
    end

    # Handling filter - stub
    def handle(input)
      return "" if input.nil?

      input.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
    end

    def handleize(input)
      handle(input)
    end

    # Weight conversion
    def weight_with_unit(input, *_args)
      "#{input} kg"
    end

    # Time/date filters
    def time_tag(input, *_args)
      %(<time>#{input}</time>)
    end

    # Article/blog filters
    def article_img_url(input, *_args)
      input.to_s
    end

    def highlight(input, *_args)
      input.to_s
    end

    def highlight_active_tag(input, *_args)
      input.to_s
    end

    # Metafield filters
    def metafield_tag(metafield, *_args)
      metafield.to_s
    end

    def metafield_text(metafield, *_args)
      metafield.to_s
    end
  end

  Liquid::Template.register_filter(ShopifyFilters)
end

LiquidSpec.configure do |config|
  config.features = [:core, :lax_parsing, :shopify_tags, :shopify_objects, :shopify_filters]
end

# Store the source during compile so we can extract schema in render
TEMPLATE_SOURCES = {}

LiquidSpec.compile do |source, options|
  template = Liquid::Template.parse(source, **options)
  TEMPLATE_SOURCES[template.object_id] = source
  template
end

LiquidSpec.render do |template, assigns, options|
  # Extract schema from template source and apply defaults to section data
  source = TEMPLATE_SOURCES[template.object_id]
  if source && assigns["section"]
    schema = SchemaDefaults.extract_schema(source)
    if schema
      assigns = assigns.dup
      assigns["section"] = SchemaDefaults.apply_defaults(assigns["section"], schema)
    end
  end

  # Build file system from registers if available
  file_system = options.dig(:registers, :file_system) || Liquid::BlankFileSystem.new

  # Build context with static_environments (read-only assigns that can be shadowed)
  context = Liquid::Context.build(
    static_environments: assigns,
    registers: Liquid::Registers.new(
      file_system: file_system,
      **(options[:registers] || {})
    ),
    rethrow_errors: options[:strict_errors],
  )
  context.exception_renderer = options[:exception_renderer] if options[:exception_renderer]

  template.render(context)
end
