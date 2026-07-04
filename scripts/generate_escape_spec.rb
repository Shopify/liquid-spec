#!/usr/bin/env ruby
# frozen_string_literal: true
# Generates the exhaustive escape / escape_once HTML-escape spectrum spec
# YAML from liquid-ruby. Covers every HTML-special character, pass-through
# of non-special characters, ordering (& first), and escape_once idempotency.
#
# Usage:  ruby scripts/generate_escape_spec.rb > specs/basics/escape.yml

require "liquid"

def r(template, env = {})
  Liquid::Template.parse(template).render(env)
end

def add(specs, name, template, expected, complexity, hint, env: nil)
  spec = { name: name, template: template, expected: expected,
           complexity: complexity, hint: hint }
  spec[:environment] = env if env
  specs << spec
end

specs = []

# ============================================================
# SECTION 1: each HTML-special character under escape
# liquid-ruby escapes: & < > " '  (& must be first to avoid double-escaping)
# ============================================================
specials = [
  ["&", "&amp;",  "ampersand (escaped FIRST so entities aren't double-escaped)"],
  ["<", "&lt;",   "less-than"],
  [">", "&gt;",   "greater-than"],
  ["\"", "&quot;", "double quote"],
  ["'", "&#39;",  "single quote (apostrophe)"],
]
specials.each do |ch, exp, label|
  env = { "ch" => ch }
  out = r("{{ ch | escape }}", env)
  add(specs, "escape_special_#{exp.sub(/[&#;]/, '')}",
      "{{ ch | escape }}", out, 70,
      "escape converts the #{label} #{ch.inspect} to #{out}.", env: env)
end

# ============================================================
# SECTION 2: non-special characters pass through unchanged
# Including control chars, high-bit, unicode — escape must NOT touch them.
# ============================================================
passthrough = [
  ["a", "plain letter"],
  ["Z", "uppercase letter"],
  ["0", "digit"],
  [" ", "space"],
  ["!", "exclamation"],
  ["#", "hash"],
  ["%", "percent"],
  ["(", "paren"],
  [")", "paren"],
  ["+", "plus"],
  ["=", "equals"],
  ["/", "slash"],
  ["@", "at"],
  ["~", "tilde"],
  ["`", "backtick"],
  ["$", "dollar"],
  ["^", "caret"],
  ["\\", "backslash"],
  ["\n", "newline"],
  ["\t", "tab"],
  ["\r", "carriage return"],
  ["\x00", "null byte"],
  ["\x7F", "DEL byte"],
  ["©", "copyright sign"],
  ["ü", "u with umlaut"],
  ["中", "cjk ideograph"],
  ["🎉", "emoji"],
]
passthrough.each do |ch, label|
  env = { "ch" => ch }
  out = r("{{ ch | escape }}", env)
  add(specs, "escape_passthrough_#{label.gsub(/[^a-z0-9]/, '_')}",
      "{{ ch | escape }}", out, 75,
      "escape passes the #{label} (#{ch.inspect}) through unchanged: #{out.inspect}.",
      env: env)
end

# ============================================================
# SECTION 3: strings containing multiple specials (ordering)
# ============================================================
multi = [
  ["a & b", "ampersand in text"],
  ["<a href=\"x\">'y'</a>", "full tag with quotes and apostrophe"],
  ["&amp;", "already-escaped ampersand (escape double-escapes it)"],
  ["5 < 3 && 2 > 1", "operators with double ampersand"],
  ["<script>alert('x')</script>", "script tag"],
]
multi.each_with_index do |(s, label), i|
  env = { "ch" => s }
  out = r("{{ ch | escape }}", env)
  add(specs, "escape_multi_#{i}",
      "{{ ch | escape }}", out, 90,
      "escape on #{label}: #{s.inspect} -> #{out.inspect}. Note & is escaped first, so already-escaped entities get double-escaped.",
      env: env)
end

# ============================================================
# SECTION 4: escape_once — does NOT re-escape already-escaped entities
# ============================================================
once_cases = [
  ["&", "&amp;", "bare ampersand gets escaped once"],
  ["&amp;", "&amp;", "already-escaped ampersand is left alone"],
  ["<", "&lt;", "bare less-than gets escaped once"],
  ["&lt;", "&lt;", "already-escaped less-than is left alone"],
  ["<b>", "&lt;b&gt;", "tag chars escaped once"],
  ["a &amp; b", "a &amp; b", "mixed bare/escaped: only bare & is escaped"],
  ["&amp;&lt;", "&amp;&lt;", "already-escaped entities left alone"],
  ["\"hello\"", "&quot;hello&quot;", "quotes escaped once"],
]
once_cases.each_with_index do |(s, exp, label), i|
  env = { "ch" => s }
  out = r("{{ ch | escape_once }}", env)
  add(specs, "escape_once_#{i}",
      "{{ ch | escape_once }}", out, 95,
      "escape_once #{label}: #{s.inspect} -> #{out.inspect}. It does not re-escape already-escaped entities.",
      env: env)
end

# ============================================================
# SECTION 5: nil / empty / non-string input
# ============================================================
add(specs, "escape_nil", "{{ missing | escape }}", r("{{ missing | escape }}"), 80,
    "escape on nil (missing var) returns empty string.")
add(specs, "escape_empty", "{{ '' | escape }}", r("{{ '' | escape }}"), 80,
    "escape on an empty string returns empty string.")
env = { "n" => 42 }
add(specs, "escape_integer", "{{ n | escape }}", r("{{ n | escape }}", env), 85,
    "escape on an integer coerces to string first ('42'), no specials to escape.",
    env: env)
env = { "arr" => [1, 2] }
add(specs, "escape_array", "{{ arr | escape }}", r("{{ arr | escape }}", env), 90,
    "escape on an array coerces to its string form ('12' for [1,2]); no specials.",
    env: env)

# ============================================================
# SECTION 6: the h alias
# ============================================================
env = { "ch" => "<b>" }
add(specs, "escape_h_alias", "{{ ch | h }}", r("{{ ch | h }}", env), 85,
    "`h` is an alias for `escape`. <b> -> &lt;b&gt;.", env: env)

# ============================================================
# Output YAML
# ============================================================
header = <<~HEADER
# Exhaustive escape / escape_once HTML-escape spectrum spec for Liquid.
#
# The entire API surface of Liquid's HTML escaping is part of the spec:
# every HTML-special character (& < > " '), the ordering rule (& first),
# pass-through of every non-special character (control bytes, high-bit,
# unicode, emoji), and escape_once idempotency. Expected values were
# captured from the reference Shopify/liquid (liquid-ruby) implementation.
#
# Reference documentation:
#   Ruby CGI.escapeHTML: https://ruby-doc.org/stdlib/libdoc/cgi/rdoc/CGI.html#method-c-escapeHTML
#   Liquid escape filter: https://shopify.dev/docs/api/liquid/filters#escape
---
_metadata:
  hint: |
    The `escape` filter HTML-escapes a string (Ruby CGI.escapeHTML-compatible).
    The entire escape spectrum is in scope: exactly five characters are
    escaped -- & < > " ' -- with & escaped FIRST (& -> &amp;) so already-escaped
    entities are NOT protected (use `escape_once` for that). Every other
    character (control bytes, unicode, emoji, punctuation) passes through
    unchanged. `escape_once` escapes bare specials but leaves already-escaped
    entities alone. `h` is an alias for `escape`. Reference:
    https://ruby-doc.org/stdlib/libdoc/cgi/rdoc/CGI.html#method-c-escapeHTML
  doc: filters/escape.md
specs:
HEADER

puts header
specs.each do |s|
  puts "- name: #{s[:name]}"
  puts "  complexity: #{s[:complexity]}"
  puts "  hint: |"
  s[:hint].split("\n").each { |line| puts "    #{line}" }
  puts "  template: #{s[:template].inspect}"
  if s[:environment]
    puts "  environment:"
    s[:environment].each { |k, v| puts "    #{k}: #{v.inspect}" }
  end
  puts "  expected: #{s[:expected].inspect}"
end
