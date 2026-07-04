#!/usr/bin/env ruby
# frozen_string_literal: true
# Generates the exhaustive url_encode / url_decode charset spec YAML from
# liquid-ruby. Covers every ASCII byte (0..127) plus multibyte UTF-8 cases.
#
# Does NOT set ENV["TZ"] (irrelevant here). Expected values are the actual
# liquid-ruby output, so the spec is self-verifying against the reference.
#
# Usage:  ruby scripts/generate_url_encode_spec.rb > specs/basics/url-encode.yml

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
# SECTION 1: every ASCII character 0..127 under url_encode
# ============================================================
# liquid-ruby's url_encode wraps Ruby's CGI.escape-compatible behavior:
# unreserved (RFC 3986) A-Z a-z 0-9 - _ . ~ pass through; everything else
# becomes %HH. Space -> +. Multibyte -> UTF-8 percent-encoding.
(0..127).each do |code|
  ch = code.chr(Encoding::UTF_8)
  printable = case code
              when 32..126 then ch
              else code.chr(Encoding::UTF_8)
              end
  env = { "ch" => ch }
  out = r("{{ ch | url_encode }}", env)
  label = if code < 32
            "ctrl_#{code}"
          elsif code == 32
            "space"
          elsif code == 126
            "tilde"
          else
            "ascii_#{code}_#{ch.inspect}"
          end
  hint = if out == ch
           "url_encode passes unreserved ASCII #{ch.inspect} (#{code}) through unchanged."
         elsif out == "+"
           "url_encode encodes space (#{code}) as '+' (form-encoding convention, not %20)."
         else
           "url_encode encodes ASCII #{ch.inspect} (#{code}) as #{out}."
         end
  add(specs, "url_encode_ascii_#{label}", "{{ ch | url_encode }}", out, 95, hint, env: env)
end

# ============================================================
# SECTION 2: multibyte UTF-8 under url_encode
# ============================================================
multibyte = [
  ["é", "U+00E9 latin small e acute"],
  ["中", "U+4E2D cjk ideograph"],
  ["🎉", "U+1F389 party popper (4-byte UTF-8)"],
  ["€", "U+20AC euro sign"],
  ["Ñ", "U+00D1 latin capital N tilde"],
  ["α", "U+03B1 greek small alpha"],
  ["\u00FF", "U+00FF latin small y diaeresis"],
]
multibyte.each do |ch, label|
  env = { "ch" => ch }
  out = r("{{ ch | url_encode }}", env)
  add(specs, "url_encode_multibyte_#{ch.ord.to_s(16)}",
      "{{ ch | url_encode }}", out, 120,
      "url_encode percent-encodes #{label} as UTF-8 bytes (#{out}).", env: env)
end

# ============================================================
# SECTION 3: url_decode round-trips and known sequences
# ============================================================
decode_cases = [
  ["%20", " "],
  ["+", "+"],
  ["%21", "!"],
  ["%2A", "*"],
  ["%C3%A9", "é"],
  ["%E4%B8%AD", "中"],
  ["hello%20world", "hello world"],
  ["a+b", "a b"],
  ["%25", "%"],
  ["", ""],
]
decode_cases.each do |enc, _|
  env = { "enc" => enc }
  out = r("{{ enc | url_decode }}", env)
  add(specs, "url_decode_#{enc.gsub(/[^a-zA-Z0-9]/, '_')}",
      "{{ enc | url_decode }}", out, 100,
      "url_decode decodes #{enc.inspect} to #{out.inspect}. (+ decodes to space; %HH to bytes.)",
      env: env)
end

# ============================================================
# SECTION 4: round-trip url_encode then url_decode
# ============================================================
rt = [["hello world", "phrase"], ["a&b=c", "with reserved"], ["é中", "multibyte"]]
rt.each do |s, label|
  env = { "ch" => s }
  out = r("{{ ch | url_encode | url_decode }}", env)
  add(specs, "url_roundtrip_#{label.gsub(/[^a-z0-9]/, '_')}",
      "{{ ch | url_encode | url_decode }}", out, 130,
      "url_encode then url_decode round-trips #{s.inspect} back to #{out.inspect}.",
      env: env)
end

# ============================================================
# SECTION 5: nil / empty / non-string input to url_encode
# ============================================================
add(specs, "url_encode_nil", "{{ missing | url_encode }}", r("{{ missing | url_encode }}"), 110,
    "url_encode on nil (missing var) returns empty string.")
add(specs, "url_encode_empty", "{{ '' | url_encode }}", r("{{ '' | url_encode }}"), 110,
    "url_encode on an empty string returns empty string.")
add(specs, "url_encode_integer", "{{ 42 | url_encode }}", r("{{ 42 | url_encode }}"), 115,
    "url_encode on an integer coerces to string first ('42').")

# ============================================================
# Output YAML
# ============================================================
header = <<~HEADER
# Exhaustive url_encode / url_decode charset spec for the Liquid filters.
#
# The entire API surface of Ruby's url-encoding (CGI.escape-compatible) is
# part of the Liquid spec: every ASCII byte 0..127, the multibyte UTF-8
# path, and the decode direction. Expected values were captured from the
# reference Shopify/liquid (liquid-ruby) implementation.
#
# Reference documentation:
#   Ruby CGI.escape: https://ruby-doc.org/stdlib/libdoc/cgi/rdoc/CGI.html#method-c-escape
#   Liquid url_encode filter: https://shopify.dev/docs/api/liquid/filters#url_encode
---
_metadata:
  hint: |
    The `url_encode` filter percent-encodes a string (Ruby CGI.escape-compatible).
    The entire encoding charset is in scope: unreserved ASCII (A-Z a-z 0-9 - _ . ~)
    passes through unchanged; every other byte becomes %HH; space becomes '+';
    multibyte characters are encoded as their UTF-8 byte sequence. `url_decode`
    reverses this ('+' and %HH -> original bytes). Reference:
    https://ruby-doc.org/stdlib/libdoc/cgi/rdoc/CGI.html#method-c-escape
  doc: filters/url_encode.md
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
