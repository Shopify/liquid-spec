#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Shopify/liquid adapter with Shopify theme filters
#
# This adapter extends the standard liquid-ruby adapter with the Shopify-specific
# filters and tags needed to run the theme benchmark suite.
#
# Run shopify filter specs:
#   liquid-spec examples/liquid_ruby_shopify.rb -s benchmarks -n shopify_
#
# Run theme benchmarks:
#   liquid-spec examples/liquid_ruby_shopify.rb -s benchmarks -n bench_theme
#
# Run as timed benchmarks:
#   liquid-spec examples/liquid_ruby_shopify.rb -s benchmarks -n bench_theme --bench
#

require "liquid/spec/cli/adapter_dsl"
require "cgi"

# ── Shopify Theme Filters ────────────────────────────────────────────────────
# Reference implementation from docs/implementers/shopify-theme-filters.md

module ShopifyThemeFilters
  def money(cents)
    return "" if cents.nil?
    format("$%.2f", cents.to_i / 100.0)
  end

  def money_with_currency(cents)
    return "" if cents.nil?
    format("$%.2f USD", cents.to_i / 100.0)
  end

  def weight_with_unit(grams)
    return "" if grams.nil?
    format("%.2f kg", grams.to_i / 1000.0)
  end

  def product_img_url(input, size = "small")
    return "/assets/no-image-#{size}.jpg" if input.nil? || input.to_s.empty?
    url = input.respond_to?(:key?) && input.key?("src") ? input["src"] : input.to_s
    basename = File.basename(url)
    filename, ext = basename =~ /\A([\w\-]+)\.(\w{2,4})\z/ ? [$1, $2] : [basename.gsub(/[^\w\-]/, ""), "jpg"]
    size.to_s == "original" ? "/files/shops/random_number/products/#{filename}.#{ext}" : "/files/shops/random_number/products/#{filename}_#{size}.#{ext}"
  end

  def img_url(input, size = "medium")
    return "/assets/no-image-#{size}.jpg" if input.nil? || input.to_s.empty?
    url = input.respond_to?(:key?) && input.key?("src") ? input["src"] : input.to_s
    basename = File.basename(url)
    filename, ext = basename =~ /\A([\w\-]+)\.(\w{2,4})\z/ ? [$1, $2] : [basename.gsub(/[^\w\-]/, ""), "jpg"]
    size.to_s == "original" ? "/assets/#{filename}.#{ext}" : "/assets/#{filename}_#{size}.#{ext}"
  end

  def asset_url(input)
    "/files/1/[shop_id]/[shop_id]/assets/#{input}"
  end

  def script_tag(url)
    %(<script src="#{CGI.escapeHTML(url.to_s)}" type="text/javascript"></script>)
  end

  def stylesheet_tag(url, media = "all")
    %(<link href="#{CGI.escapeHTML(url.to_s)}" rel="stylesheet" type="text/css"  media="#{CGI.escapeHTML(media.to_s)}"  />)
  end

  def handle(str)
    return "" if str.nil?
    result = str.to_s.dup
    result.downcase!
    result.delete!("'\"()[]")
    result.gsub!(/\W+/, "-")
    result.gsub!(/\A-+|-+\z/, "")
    result
  end

  def pluralize(count, singular, plural)
    count.to_i == 1 ? singular : plural
  end

  def default_pagination(paginate)
    return "" unless paginate.is_a?(Hash) && paginate["parts"].is_a?(Array)
    html = []
    if (prev = paginate["previous"]) && prev["url"]
      t = CGI.escapeHTML(prev["title"].to_s)
      html << %(<span class="prev"><a href="#{prev["url"]}" title="#{t}">#{t}</a></span>)
    end
    paginate["parts"].each do |part|
      t = CGI.escapeHTML(part["title"].to_s)
      if part["is_link"] && part["url"]
        html << %(<span class="page"><a href="#{part["url"]}" title="#{t}">#{t}</a></span>)
      elsif part["title"].to_s == paginate["current_page"].to_s
        html << %(<span class="page current">#{t}</span>)
      else
        html << %(<span class="deco">#{t}</span>)
      end
    end
    if (nxt = paginate["next"]) && nxt["url"]
      t = CGI.escapeHTML(nxt["title"].to_s)
      html << %(<span class="next"><a href="#{nxt["url"]}" title="#{t}">#{t}</a></span>)
    end
    html.join(" ")
  end
end

# ── Adapter Setup ────────────────────────────────────────────────────────────

LiquidSpec.setup do |ctx|
  require "liquid"

  if defined?(Liquid::C) && Liquid::C.respond_to?(:enabled=)
    Liquid::C.enabled = false
  end

  env = Liquid::Environment.default
  env.register_filter(ShopifyThemeFilters)

  # Paginate block tag — defined here after Liquid is loaded
  klass = Class.new(Liquid::Block) do
    Syntax = /(#{Liquid::QuotedFragment})\s+by\s+(\d+)/

    def initialize(tag_name, markup, options)
      super
      if markup =~ Syntax
        @collection_name = Regexp.last_match(1)
        @page_size = Regexp.last_match(2).to_i
      else
        raise Liquid::SyntaxError, "Valid syntax: paginate [collection] by [number]"
      end
    end

    def render_to_output_buffer(context, output)
      collection = context[@collection_name]
      return super unless collection.respond_to?(:size)

      page_size = @page_size
      current_page = [(context["current_page"] || 1).to_i, 1].max
      total_items = collection.size
      total_pages = page_size > 0 ? (total_items.to_f / page_size).ceil : 1
      total_pages = 1 if total_pages == 0 && total_items > 0

      paginate = {
        "page_size" => page_size, "current_page" => current_page,
        "current_offset" => (current_page - 1) * page_size,
        "items" => total_items, "pages" => total_pages,
        "previous" => nil, "next" => nil, "parts" => [],
      }

      paginate["previous"] = { "title" => "&laquo; Previous", "url" => "?page=#{current_page - 1}", "is_link" => true } if current_page > 1
      paginate["next"] = { "title" => "Next &raquo;", "url" => "?page=#{current_page + 1}", "is_link" => true } if current_page < total_pages

      window = 3
      hellip = false
      1.upto(total_pages) do |pg|
        if current_page == pg
          paginate["parts"] << { "title" => pg.to_s, "is_link" => false }
          hellip = false
        elsif pg == 1 || pg == total_pages || (pg >= current_page - window && pg <= current_page + window)
          paginate["parts"] << { "title" => pg.to_s, "url" => "?page=#{pg}", "is_link" => true }
          hellip = false
        elsif !hellip
          paginate["parts"] << { "title" => "&hellip;", "is_link" => false }
          hellip = true
        end
      end

      offset = (current_page - 1) * page_size
      sliced = collection.drop(offset).take(page_size)

      context.stack do
        context[@collection_name] = sliced
        context["paginate"] = paginate
        super
      end
    end
  end

  env.register_tag("paginate", klass)
  ctx[:paginate_tag] = klass
end

LiquidSpec.configure do |config|
  config.features = [:core, :strict_parsing, :ruby_types, :shopify_filters]
  config.suites = [:benchmarks]
  config.filter = "shopify_"
end

LiquidSpec.compile do |ctx, source, parse_options|
  # Build a custom environment with our filters taking precedence over stubs
  unless ctx[:shopify_env]
    ctx[:shopify_env] = Liquid::Environment.build do |env|
      env.register_filter(ShopifyThemeFilters)
      env.register_tag("paginate", ctx[:paginate_tag])
    end
  end
  ctx[:template] = Liquid::Template.parse(
    source, **parse_options, error_mode: :strict, environment: ctx[:shopify_env],
  )
end

LiquidSpec.render do |ctx, assigns, render_options|
  context = Liquid::Context.build(
    environment: ctx[:shopify_env],
    static_environments: assigns,
    registers: Liquid::Registers.new(render_options[:registers] || {}),
    rethrow_errors: render_options[:strict_errors],
  )
  context.exception_renderer = render_options[:exception_renderer] if render_options[:exception_renderer]
  ctx[:template].render(context)
end
