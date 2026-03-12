#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates specs/benchmarks/_data/theme_database.yml
# A large, realistic Shopify theme database for benchmark specs.
#
# Data shapes match real Shopify Liquid objects:
# - Prices in cents (19900 = $199.00) — use | money filter to format
# - Images as path strings — use | product_img_url / img_url filters
# - Handles match Shopify's handleize behavior

require "yaml"

srand(42) # Deterministic randomness for reproducible output

VENDORS = %w[Arbor Technine Burton Shopify Stormtech Ducati Nikon Jones Capita Rome LibTech GNU Ride Nitro K2 Salomon Rossignol Flow DC Vans ThirtyTwo Volcom Billabong Quiksilver Oakley Smith Electric Anon Giro]
PRODUCT_TYPES = %w[Snowboards Boots Bindings Goggles Helmets Jackets Pants Gloves Shirts Sweaters Accessories Bags Cameras Bikes]
COLORS = %w[Black White Red Blue Green Navy Gray Brown Beige Orange Purple Pink Teal Olive Maroon Charcoal Ivory Slate Coral Sage]
SIZES = %w[XS S M L XL XXL]

ADJECTIVES = %w[Pro Elite Premium Ultra Classic Vintage Modern Swift Storm Thunder Shadow Phantom Apex Summit Ridge Glacier Peak Drift Blaze Fury Titan Nova Pulse Zenith Vortex Echo]
NOUNS = %w[Draft Element Rider Cruiser Carver Shredder Glider Ranger Explorer Nomad Voyager Pioneer Rebel Maverick Legend Icon Catalyst Prodigy Summit Venture Fusion Forge]

TAGS_POOL = %w[season2024 season2025 pro beginner intermediate advanced freestyle freeride all-mountain powder park backcountry racing street urban lightweight durable waterproof windproof insulated breathable recycled eco-friendly new-arrival best-seller limited-edition sale clearance]

def handleize(str)
  str.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
end

db = {}

# ============================================================
# Products (120 products with realistic variants and options)
# Prices in CENTS (Shopify convention)
# Images as raw path strings (use product_img_url filter)
# ============================================================
products = []
variant_id = 1

120.times do |i|
  pid = i + 1
  vendor = VENDORS[i % VENDORS.size]
  ptype = PRODUCT_TYPES[i % PRODUCT_TYPES.size]
  adj = ADJECTIVES[i % ADJECTIVES.size]
  noun = NOUNS[i % NOUNS.size]
  title = "#{vendor} #{adj} #{noun}"
  handle = handleize(title)

  # Prices in cents
  base_price_cents = (2000 + (i * 700) % 50000)
  has_sale = i % 3 == 0
  compare_at_cents = has_sale ? (base_price_cents * 1.4).to_i : nil

  # Options based on product type
  options_with_values = case ptype
  when "Snowboards"
    lengths = %w[148cm 151cm 154cm 157cm 160cm 163cm].sample(3 + i % 3)
    [
      { "name" => "Length", "values" => lengths },
      { "name" => "Style", "values" => %w[Regular Wide Mid-Wide] },
    ]
  when "Boots", "Bindings"
    [
      { "name" => "Size", "values" => (6..14).map(&:to_s) },
      { "name" => "Color", "values" => COLORS.sample(3 + i % 4) },
    ]
  when "Goggles", "Helmets"
    [
      { "name" => "Size", "values" => %w[S M L XL] },
      { "name" => "Color", "values" => COLORS.sample(4 + i % 3) },
    ]
  when "Jackets", "Pants"
    [
      { "name" => "Size", "values" => SIZES.dup },
      { "name" => "Color", "values" => COLORS.sample(5 + i % 4) },
      { "name" => "Fit", "values" => %w[Regular Slim Relaxed] },
    ]
  when "Shirts", "Sweaters"
    [
      { "name" => "Size", "values" => SIZES.dup },
      { "name" => "Color", "values" => COLORS.sample(4 + i % 5) },
    ]
  when "Cameras"
    [{ "name" => "Bundle", "values" => ["Body Only", "Kit with 18-55mm lens", "Kit with 18-200mm lens", "Kit with 24-70mm lens", "Pro Bundle"] }]
  when "Bikes"
    [
      { "name" => "Frame Size", "values" => %w[48cm 52cm 54cm 56cm 58cm 60cm] },
      { "name" => "Color", "values" => COLORS.sample(4) },
    ]
  else
    [{ "name" => "Color", "values" => COLORS.sample(3 + i % 4) }]
  end

  # Generate variants (cross-product of first 2 option dimensions, capped at 20)
  variants = []
  opt1 = options_with_values[0]["values"]
  opt2 = options_with_values.size > 1 ? options_with_values[1]["values"] : [nil]
  opt1.each do |v1|
    opt2.each do |v2|
      break if variants.size >= 20
      vtitle = [v1, v2].compact.join(" / ")
      vprice = base_price_cents + (variants.size * 500) % 3000
      available = variants.size % 5 != 4 # 80% available
      variants << {
        "id" => variant_id,
        "title" => vtitle,
        "price" => vprice,
        "weight" => 500 + (i * 100) % 5000,
        "compare_at_price" => has_sale ? (vprice * 1.4).to_i : nil,
        "available" => available,
        "inventory_quantity" => available ? (1 + variants.size % 20) : 0,
        "option1" => v1,
        "option2" => v2,
        "option3" => nil,
      }
      variant_id += 1
    end
  end

  tags = TAGS_POOL.sample(4 + i % 5)

  description = <<~DESC.strip
    <p>The #{title} is our latest #{ptype.downcase.chomp("s")} from #{vendor}. Designed for performance and versatility, this #{ptype.downcase.chomp("s")} delivers exceptional quality in any conditions.</p>
    <p>Featuring advanced technology and a refined design. Perfect for beginners and advanced riders. Available in #{options_with_values[0]["values"].size} #{options_with_values[0]["name"].downcase} options#{options_with_values.size > 1 ? " and #{options_with_values[1]["values"].size} #{options_with_values[1]["name"].downcase} choices" : ""}.</p>
  DESC

  num_images = 2 + i % 4
  images = (1..num_images).map { |idx| "products/#{handle}_#{idx}.jpg" }

  # Price is in cents; price_min/price_max from variants
  prices = variants.map { |v| v["price"] }

  product = {
    "id" => pid,
    "title" => title,
    "handle" => handle,
    "type" => ptype,
    "vendor" => vendor,
    "price" => prices.min,
    "price_min" => prices.min,
    "price_max" => prices.max,
    "price_varies" => prices.min != prices.max,
    "compare_at_price" => compare_at_cents,
    "compare_at_price_max" => has_sale ? variants.map { |v| v["compare_at_price"] }.compact.max : 0,
    "compare_at_price_min" => has_sale ? variants.map { |v| v["compare_at_price"] }.compact.min : 0,
    "compare_at_price_varies" => has_sale && variants.map { |v| v["compare_at_price"] }.compact.uniq.size > 1,
    "available" => variants.any? { |v| v["available"] },
    "has_only_default_variant" => variants.size == 1,
    "url" => "/products/#{handle}",
    "featured_image" => "products/#{handle}.jpg",
    "images" => images,
    "description" => description,
    "tags" => tags,
    "options" => options_with_values.map { |o| o["name"] },
    "options_with_values" => options_with_values,
    "variants" => variants,
  }
  products << product
end

db["products"] = products

# ============================================================
# Collections (varying sizes, includes large 120-product collection)
# ============================================================
collections = {}

collections["frontpage"] = {
  "title" => "Frontpage",
  "url" => "/collections/frontpage",
  "handle" => "frontpage",
  "description" => "",
  "products_count" => 12,
  "products" => products[0..11],
}

collections["all"] = {
  "title" => "All Products",
  "url" => "/collections/all",
  "handle" => "all",
  "description" => "<p>Browse our complete catalog of #{products.size} products.</p>",
  "products_count" => products.size,
  "products" => products,
}

# Type-based collections
PRODUCT_TYPES.each do |ptype|
  typed = products.select { |p| p["type"] == ptype }
  next if typed.empty?

  handle = handleize(ptype)
  collections[handle] = {
    "title" => ptype,
    "url" => "/collections/#{handle}",
    "handle" => handle,
    "description" => "<p>Our full range of #{ptype.downcase}.</p>",
    "products_count" => typed.size,
    "products" => typed,
  }
end

# Sale collection
sale_products = products.select { |p| p["compare_at_price"] && p["compare_at_price"] > 0 }
collections["sale"] = {
  "title" => "Items On Sale",
  "url" => "/collections/sale",
  "handle" => "sale",
  "description" => "<p>Don't miss our latest deals and discounts.</p>",
  "products_count" => sale_products.size,
  "products" => sale_products,
}

db["collections"] = collections

# ============================================================
# Shop
# ============================================================
db["shop"] = {
  "name" => "Shopify Test Store",
  "description" => "Premium outdoor gear and apparel from top brands worldwide.",
  "email" => "support@example.com",
  "phone" => "555-123-4567",
  "url" => "https://shopify-test-store.myshopify.com",
  "address" => {
    "street" => "150 Elgin Street",
    "city" => "Ottawa",
    "province" => "Ontario",
    "zip" => "K2P 1L4",
    "country" => "Canada",
  },
  "metafields" => {
    "theme" => {
      "announcement_text" => "Free shipping on all orders over $100!",
    },
  },
}

# ============================================================
# Linklists (navigation menus)
# ============================================================
db["linklists"] = {
  "main-menu" => {
    "links" => [
      { "title" => "Catalog", "url" => "/collections/all" },
      { "title" => "Snowboards", "url" => "/collections/snowboards" },
      { "title" => "Boots", "url" => "/collections/boots" },
      { "title" => "Apparel", "url" => "/collections/jackets" },
      { "title" => "Sale", "url" => "/collections/sale" },
      { "title" => "About Us", "url" => "/pages/about-us" },
      { "title" => "Blog", "url" => "/blogs/news" },
    ],
  },
  "footer" => {
    "links" => [
      { "title" => "About Us", "url" => "/pages/about-us" },
      { "title" => "Shipping & Returns", "url" => "/pages/shipping" },
      { "title" => "Privacy Policy", "url" => "/pages/privacy" },
      { "title" => "Terms of Service", "url" => "/pages/terms" },
    ],
  },
}

# ============================================================
# Cart (3 items, prices in cents)
# ============================================================
cart_items = [
  {
    "key" => "#{products[0]["handle"]}-var-#{products[0]["variants"][0]["id"]}",
    "url" => products[0]["url"],
    "image" => products[0]["images"][0],
    "title" => "#{products[0]["title"]} - #{products[0]["variants"][0]["title"]}",
    "product" => { "title" => products[0]["title"] },
    "variant" => { "title" => products[0]["variants"][0]["title"] },
    "quantity" => 1,
    "price" => products[0]["variants"][0]["price"],
    "line_price" => products[0]["variants"][0]["price"],
  },
  {
    "key" => "#{products[2]["handle"]}-var-#{products[2]["variants"][0]["id"]}",
    "url" => products[2]["url"],
    "image" => products[2]["images"][0],
    "title" => "#{products[2]["title"]} - #{products[2]["variants"][0]["title"]}",
    "product" => { "title" => products[2]["title"] },
    "variant" => { "title" => products[2]["variants"][0]["title"] },
    "quantity" => 2,
    "price" => products[2]["variants"][0]["price"],
    "line_price" => products[2]["variants"][0]["price"] * 2,
  },
  {
    "key" => "#{products[4]["handle"]}-var-#{products[4]["variants"][0]["id"]}",
    "url" => products[4]["url"],
    "image" => products[4]["images"][0],
    "title" => "#{products[4]["title"]} - #{products[4]["variants"][0]["title"]}",
    "product" => { "title" => products[4]["title"] },
    "variant" => { "title" => products[4]["variants"][0]["title"] },
    "quantity" => 1,
    "price" => products[4]["variants"][0]["price"],
    "line_price" => products[4]["variants"][0]["price"],
  },
]

total_cents = cart_items.sum { |i| i["line_price"] }
db["cart"] = {
  "item_count" => cart_items.sum { |i| i["quantity"] },
  "total_price" => total_cents,
  "items" => cart_items,
}

# ============================================================
# Blog with 20 articles
# ============================================================
article_titles = [
  "Welcome to Our New Store", "Top 10 Snowboards for This Season",
  "How to Choose the Right Snowboard Size", "Beginner's Guide to Snowboarding",
  "Best Snowboard Boots Reviewed", "Understanding Snowboard Flex Patterns",
  "Snowboard Maintenance Tips", "The History of Snowboarding",
  "Park Riding vs Backcountry: A Comparison", "Interview with Pro Rider Alex Storm",
  "New Product Launch: Arbor 2025 Collection", "Snowboard Safety Equipment Guide",
  "Best Resorts for Snowboarding", "How to Wax Your Snowboard",
  "Choosing Bindings for Your Style", "Layering for Cold Weather Riding",
  "Eco-Friendly Snowboard Brands", "Summer Training for Snowboarders",
  "Kids Snowboarding: Getting Started", "End of Season Sale Announcement",
]
authors = %w[Daniel Tobi Justin Sarah Emily]

articles = article_titles.each_with_index.map do |title, i|
  handle = handleize(title)
  {
    "id" => i + 1,
    "title" => title,
    "handle" => handle,
    "author" => authors[i % authors.size],
    "url" => "/blogs/news/#{handle}",
    "published_at" => "2024-#{format("%02d", (1 + i / 2).clamp(1, 12))}-#{format("%02d", (1 + i).clamp(1, 28))}",
    "image" => i % 4 != 3 ? { "src" => "blogs/news/#{handle}.jpg" } : nil,
    "excerpt" => i.even? ? "A brief summary of #{title.downcase}. Read on to learn more." : "",
    "content" => "<p>#{title} — Full article content. Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</p><p>Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>",
    "comments_count" => i + 2,
  }
end

db["blog"] = {
  "title" => "News",
  "url" => "/blogs/news",
  "handle" => "news",
  "articles_count" => articles.size,
  "articles" => articles,
  "comments_enabled" => true,
}

# ============================================================
# Search results (mix of products and pages)
# ============================================================
search_product_results = products[0..19].map do |p|
  {
    "object_type" => "product",
    "id" => p["id"],
    "title" => p["title"],
    "handle" => p["handle"],
    "url" => p["url"],
    "price" => p["price"],
    "compare_at_price" => p["compare_at_price"],
    "featured_image" => p["featured_image"],
    "available" => p["available"],
    "variants" => [p["variants"].first],
  }
end

search_page_results = [
  { "object_type" => "page", "title" => "Contact Us", "url" => "/pages/contact", "content" => "<p>You can contact us via phone at (555) 567-2222.</p>" },
  { "object_type" => "page", "title" => "About Us", "url" => "/pages/about-us", "content" => "<p>Founded in 1894, operating from Avignon, Provence.</p>" },
  { "object_type" => "page", "title" => "Shipping", "url" => "/pages/shipping", "content" => "<p>Free shipping on orders over $100. Standard 3-7 days.</p>" },
  { "object_type" => "page", "title" => "Returns Policy", "url" => "/pages/returns", "content" => "<p>30-day returns on unused items in original packaging.</p>" },
  { "object_type" => "page", "title" => "FAQ", "url" => "/pages/faq", "content" => "<p>Frequently asked questions about products and shipping.</p>" },
]

all_search_results = search_product_results + search_page_results

db["search"] = {
  "terms" => "snowboard",
  "performed" => true,
  "results_count" => all_search_results.size,
  "results" => all_search_results,
}

# ============================================================
# Extra layout / page variables
# ============================================================
db["page_title"] = "Shopify Test Store"
db["canonical_url"] = "https://shopify-test-store.myshopify.com"
db["template"] = "index"
db["content_for_header"] = '<meta name="shopify-digital-wallet" content="/checkout"><link rel="preconnect" href="https://cdn.shopify.com">'
db["current_page"] = 1

db["page"] = {
  "title" => "About Us",
  "content" => "<p>Founded in 1894, operating from Avignon, Provence. We offer the highest quality products.</p>",
}

# Convenience top-level keys (like Shopify's database.rb does)
# These give templates direct access to a single product/collection/article
db["product"] = products.first
db["collection"] = collections["all"]
db["article"] = articles.first

# ============================================================
# Write output
# ============================================================
output_path = File.join(__dir__, "..", "specs", "benchmarks", "_data", "theme_database.yml")
variant_count = products.sum { |p| p["variants"].size }
header = <<~HEADER
  # Auto-generated Shopify Dream theme benchmark database
  # Generated by: ruby scripts/generate_theme_database.rb
  #
  # #{products.size} products, #{variant_count} variants
  # #{collections.size} collections (largest: #{collections.values.map { |c| c["products"].size }.max} products)
  # #{articles.size} blog articles, #{all_search_results.size} search results
  #
  # Data shapes match real Shopify Liquid objects:
  #   Prices: integer cents (19900 = $199.00) — use | money filter
  #   Images: path strings ("products/foo.jpg") — use | product_img_url / img_url
  #   Handles: lowercase-hyphenated — use | handle filter
HEADER

File.write(output_path, header + YAML.dump(db))

puts "Generated #{output_path}"
puts "  #{products.size} products, #{variant_count} variants"
puts "  #{collections.size} collections (largest: #{collections.values.map { |c| c["products"].size }.max} products)"
puts "  #{articles.size} blog articles"
puts "  #{all_search_results.size} search results"
puts "  File size: #{(File.size(output_path) / 1024.0).round(1)} KB"
