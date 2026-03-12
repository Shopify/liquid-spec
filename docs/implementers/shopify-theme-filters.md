---
title: Shopify Theme Filters Reference
description: >
  Reference implementation for Shopify-specific filters and tags needed by the
  theme benchmark suite. Provides working Ruby code that can serve as pseudocode
  for any language.
optional: true
order: 20
---

# Shopify Theme Filters

The theme benchmark templates (`specs/benchmarks/theme_*.yml`) use Shopify-specific filters and
tags that are not part of core Liquid. This document provides a complete reference implementation
in Ruby that can serve as pseudocode for implementing these in any language.

These are required when your adapter declares `features: [:shopify_filters]`.

---

## Complete Reference Implementation

The following Ruby module implements all required filters. Register it with your Liquid
environment to pass the `shopify_helpers.yml` specs and run the theme benchmarks.

```ruby
# Reference implementation of Shopify theme filters.
# Register with: Liquid::Template.register_filter(ShopifyThemeFilters)

require "cgi"

module ShopifyThemeFilters
  # ============================================================
  # Money Filters
  # ============================================================

  # Formats cents as dollars: 19900 → "$199.00"
  # Input: integer (cents) or nil
  # Output: formatted string with $ prefix and 2 decimal places
  def money(cents)
    return "" if cents.nil?
    format("$%.2f", cents.to_i / 100.0)
  end

  # Like money but appends currency: 19900 → "$199.00 USD"
  def money_with_currency(cents)
    return "" if cents.nil?
    format("$%.2f USD", cents.to_i / 100.0)
  end

  # ============================================================
  # Weight Filters
  # ============================================================

  # Converts grams to kg: 1500 → "1.50 kg"
  def weight_with_unit(grams)
    return "" if grams.nil?
    format("%.2f kg", grams.to_i / 1000.0)
  end

  # ============================================================
  # Image URL Filters
  # ============================================================

  # Generates product image URLs with size variants.
  #
  # Input: image path string (e.g., "products/arbor_draft.jpg")
  #        OR a hash/object with a "src" key
  # Size:  one of: original, grande, large, medium, compact, small, thumb, icon
  #
  # Output for size "original":
  #   "/files/shops/random_number/products/{filename}.{ext}"
  # Output for other sizes:
  #   "/files/shops/random_number/products/{filename}_{size}.{ext}"
  def product_img_url(input, size = "small")
    return "/assets/no-image-#{size}.jpg" if input.nil? || input.to_s.empty?

    # Handle hash/object input with "src" key
    url = if input.respond_to?(:key?) && input.key?("src")
      input["src"]
    else
      input.to_s
    end

    # Extract filename and extension from the path
    basename = File.basename(url)
    if basename =~ /\A([\w\-]+)\.(\w{2,4})\z/
      filename = $1
      ext = $2
    else
      filename = basename.gsub(/[^\w\-]/, "")
      ext = "jpg"
    end

    if size.to_s == "original"
      "/files/shops/random_number/products/#{filename}.#{ext}"
    else
      "/files/shops/random_number/products/#{filename}_#{size}.#{ext}"
    end
  end

  # Generic image URL filter (for articles, blogs, etc.)
  #
  # Input: image path string OR hash with "src" key
  # Size:  same options as product_img_url
  #
  # Output for "original": "/assets/{filename}.{ext}"
  # Output for other sizes: "/assets/{filename}_{size}.{ext}"
  def img_url(input, size = "medium")
    return "/assets/no-image-#{size}.jpg" if input.nil? || input.to_s.empty?

    url = if input.respond_to?(:key?) && input.key?("src")
      input["src"]
    else
      input.to_s
    end

    basename = File.basename(url)
    if basename =~ /\A([\w\-]+)\.(\w{2,4})\z/
      filename = $1
      ext = $2
    else
      filename = basename.gsub(/[^\w\-]/, "")
      ext = "jpg"
    end

    if size.to_s == "original"
      "/assets/#{filename}.#{ext}"
    else
      "/assets/#{filename}_#{size}.#{ext}"
    end
  end

  # ============================================================
  # Asset Filters
  # ============================================================

  # Generates an asset URL path.
  # Input: filename string (e.g., "theme.css")
  # Output: "/files/1/[shop_id]/[shop_id]/assets/{filename}"
  def asset_url(input)
    "/files/1/[shop_id]/[shop_id]/assets/#{input}"
  end

  # ============================================================
  # HTML Tag Filters
  # ============================================================

  # Wraps a URL in a <script> tag.
  def script_tag(url)
    %(<script src="#{CGI.escapeHTML(url.to_s)}" type="text/javascript"></script>)
  end

  # Wraps a URL in a <link> stylesheet tag.
  def stylesheet_tag(url, media = "all")
    %(<link href="#{CGI.escapeHTML(url.to_s)}" rel="stylesheet" type="text/css"  media="#{CGI.escapeHTML(media.to_s)}"  />)
  end

  # ============================================================
  # String Filters
  # ============================================================

  # Converts a string to a URL-safe handle.
  #
  # Algorithm:
  #   1. Downcase
  #   2. Remove: ' " ( ) [ ]
  #   3. Replace non-word characters (\W+) with hyphens
  #   4. Strip leading/trailing hyphens
  #
  # "Season 2005" → "season-2005"
  # "Arbor Draft"  → "arbor-draft"
  # "It's a Test"  → "its-a-test"
  def handle(str)
    return "" if str.nil?
    result = str.to_s.dup
    result.downcase!
    result.delete!("'\"()[]")
    result.gsub!(/\W+/, "-")
    result.gsub!(/\A-+|-+\z/, "")
    result
  end

  # Returns singular or plural form based on count.
  # {{ 1 | pluralize: "item", "items" }} → "item"
  # {{ 5 | pluralize: "item", "items" }} → "items"
  def pluralize(count, singular, plural)
    count.to_i == 1 ? singular : plural
  end

  # ============================================================
  # Pagination Filter
  # ============================================================

  # Renders pagination HTML from a paginate object.
  #
  # Input: paginate hash with keys:
  #   current_page, pages, previous, next, parts
  #
  # Each "part" has: title, url (optional), is_link (boolean)
  # "previous"/"next" have: title, url, is_link
  #
  # Output: HTML spans joined with spaces:
  #   <span class="prev"><a href="..." title="...">...</a></span>
  #   <span class="page"><a href="..." title="...">...</a></span>
  #   <span class="page current">1</span>
  #   <span class="deco">&hellip;</span>
  #   <span class="next"><a href="..." title="...">...</a></span>
  def default_pagination(paginate)
    return "" unless paginate.is_a?(Hash) && paginate["parts"].is_a?(Array)

    html = []

    if paginate["previous"] && paginate["previous"]["url"]
      prev_title = CGI.escapeHTML(paginate["previous"]["title"].to_s)
      html << %(<span class="prev"><a href="#{paginate["previous"]["url"]}" title="#{prev_title}">#{prev_title}</a></span>)
    end

    paginate["parts"].each do |part|
      title = CGI.escapeHTML(part["title"].to_s)
      if part["is_link"] && part["url"]
        html << %(<span class="page"><a href="#{part["url"]}" title="#{title}">#{title}</a></span>)
      elsif part["title"].to_s == paginate["current_page"].to_s
        html << %(<span class="page current">#{title}</span>)
      else
        html << %(<span class="deco">#{title}</span>)
      end
    end

    if paginate["next"] && paginate["next"]["url"]
      next_title = CGI.escapeHTML(paginate["next"]["title"].to_s)
      html << %(<span class="next"><a href="#{paginate["next"]["url"]}" title="#{next_title}">#{next_title}</a></span>)
    end

    html.join(" ")
  end
end
```

---

## Paginate Block Tag

The `{% paginate %}` tag is a block tag that slices a collection for the current page
and provides pagination metadata. This is more complex than a filter — it requires
custom tag parsing and context management.

### Syntax

```liquid
{% paginate collection.products by 12 %}
  {% for product in collection.products %}
    {{ product.title }}
  {% endfor %}
  {{ paginate | default_pagination }}
{% endpaginate %}
```

### Implementation

```ruby
# Register with: Liquid::Template.register_tag("paginate", PaginateTag)

class PaginateTag < Liquid::Block
  SYNTAX = /(#{Liquid::QuotedFragment})\s+by\s+(\d+)/

  def initialize(tag_name, markup, options)
    super
    if markup =~ SYNTAX
      @collection_name = Regexp.last_match(1)
      @page_size = Regexp.last_match(2).to_i
    else
      raise SyntaxError, "Valid syntax: paginate [collection] by [number]"
    end
  end

  def render_to_output_buffer(context, output)
    collection = context[@collection_name]
    return super unless collection.respond_to?(:size)

    page_size = @page_size
    current_page = (context["current_page"] || 1).to_i
    current_page = 1 if current_page < 1

    total_items = collection.size
    total_pages = (total_items.to_f / page_size).ceil
    total_pages = 1 if total_pages == 0 && total_items > 0

    # Build pagination metadata
    paginate = {
      "page_size"    => page_size,
      "current_page" => current_page,
      "current_offset" => (current_page - 1) * page_size,
      "items"        => total_items,
      "pages"        => total_pages,
      "previous"     => nil,
      "next"         => nil,
      "parts"        => [],
    }

    if current_page > 1
      paginate["previous"] = {
        "title"   => "&laquo; Previous",
        "url"     => "?page=#{current_page - 1}",
        "is_link" => true,
      }
    end

    if current_page < total_pages
      paginate["next"] = {
        "title"   => "Next &raquo;",
        "url"     => "?page=#{current_page + 1}",
        "is_link" => true,
      }
    end

    # Build page number parts with ellipsis for large page counts
    window_size = 3
    hellip_break = false
    1.upto(total_pages) do |page|
      is_current    = current_page == page
      is_first_last = page == 1 || page == total_pages
      is_in_window  = page >= current_page - window_size &&
                      page <= current_page + window_size

      if is_current
        paginate["parts"] << { "title" => page.to_s, "is_link" => false }
        hellip_break = false
      elsif is_first_last || is_in_window
        paginate["parts"] << {
          "title"   => page.to_s,
          "url"     => "?page=#{page}",
          "is_link" => true,
        }
        hellip_break = false
      elsif !hellip_break
        paginate["parts"] << { "title" => "&hellip;", "is_link" => false }
        hellip_break = true
      end
    end

    # Slice collection for current page and render block
    offset = (current_page - 1) * page_size
    sliced = collection.drop(offset).take(page_size)

    context.stack do
      context[@collection_name] = sliced
      context["paginate"] = paginate
      super
    end
  end
end
```

### Key behaviors

| Aspect | Behavior |
|--------|----------|
| Page source | Reads `current_page` from context (default: 1) |
| Collection slicing | `drop(offset).take(page_size)` on the original array |
| Page parts | Window of 3 pages around current, ellipsis for gaps |
| Previous/Next | Only present when there is a preceding/following page |
| Context scope | `paginate` variable and sliced collection are scoped to the block |

---

## Filter Summary

| Filter | Input | Output | Example |
|--------|-------|--------|---------|
| `money` | cents (int) | `"$X.XX"` | `19900 → "$199.00"` |
| `money_with_currency` | cents (int) | `"$X.XX USD"` | `19900 → "$199.00 USD"` |
| `weight_with_unit` | grams (int) | `"X.XX kg"` | `1500 → "1.50 kg"` |
| `product_img_url` | path (str), size | URL string | `"foo.jpg", "small" → ".../foo_small.jpg"` |
| `img_url` | path/hash, size | URL string | `"bar.jpg", "medium" → "/assets/bar_medium.jpg"` |
| `asset_url` | filename (str) | URL string | `"theme.css" → "/files/1/.../assets/theme.css"` |
| `script_tag` | URL (str) | `<script>` HTML | wraps in script tag |
| `stylesheet_tag` | URL (str) | `<link>` HTML | wraps in link tag |
| `handle` | string | handle string | `"Season 2005" → "season-2005"` |
| `pluralize` | count, singular, plural | string | `1, "item", "items" → "item"` |
| `default_pagination` | paginate hash | HTML string | renders page links |
