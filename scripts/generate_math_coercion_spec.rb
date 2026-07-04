#!/usr/bin/env ruby
# frozen_string_literal: true
# Generates the exhaustive math-filter type-coercion matrix spec YAML from
# liquid-ruby. Covers every math operation x every input type, locking down
# liquid-ruby's quirky coercion rules (non-numeric/nil/bool/array -> 0 via
# to_i; divided_by does integer division when both operands are integers).
#
# Usage:  ruby scripts/generate_math_coercion_spec.rb > specs/basics/math-coercion.yml

require "liquid"

def r(template, env = {})
  Liquid::Template.parse(template).render(env)
end

def add(specs, name, template, expected, complexity, hint, env: nil, render_errors: nil)
  spec = { name: name, template: template, expected: expected,
           complexity: complexity, hint: hint }
  spec[:environment] = env if env
  spec[:render_errors] = render_errors if render_errors
  specs << spec
end

specs = []

# Input types exercised as the LEFT operand. RIGHT operand is a plain Integer 3
# (and a Float 3.0 for divided_by to show the int-vs-float division quirk).
TYPES = [
  ["int",          5,    "Integer"],
  ["float",        5.0,  "Float"],
  ["numeric_str",  "5",  "numeric String ('5')"],
  ["nonnum_str",   "foo","non-numeric String ('foo') -> to_i = 0"],
  ["nil",          nil,  "nil -> coerced to 0"],
  ["true",         true, "true -> to_i = 0 (not 1!)"],
  ["false",        false,"false -> to_i = 0"],
  ["empty_str",    "",   "empty String -> to_i = 0"],
  ["array",        [1,2,3], "Array -> to_i = 0"],
].freeze

BINARY = [
  ["plus",        "addition"],
  ["minus",       "subtraction"],
  ["times",       "multiplication"],
  ["divided_by",  "division (integer division when BOTH operands are integers)"],
  ["modulo",      "modulo"],
  ["at_least",    "lower bound (max of left, right)"],
  ["at_most",     "upper bound (min of left, right)"],
].freeze

UNARY = ["abs", "ceil", "floor", "round"].freeze

# ============================================================
# SECTION 1: binary ops, LEFT = each type, RIGHT = Integer 3
# ============================================================
BINARY.each do |op, desc|
  TYPES.each do |label, val, typedesc|
    env = { "x" => val }
    tmpl = "{{ x | #{op}: 3 }}"
    out = r(tmpl, env)
    add(specs, "math_#{op}_left_#{label}_right_int",
        tmpl, out, 130,
        "#{op} (#{desc}): left = #{typedesc}, right = Integer 3 -> #{out.inspect}.",
        env: env)
  end
end

# ============================================================
# SECTION 2: divided_by int-vs-float operand quirk (the big one)
# Integer / Integer -> integer division; any Float operand -> float division.
# ============================================================
div_cases = [
  ["int",   10,  "int",   3,   "10 / 3   -> integer division (truncated)"],
  ["int",   10,  "float", 3.0, "10 / 3.0 -> float division"],
  ["float", 10.0,"int",   3,   "10.0 / 3 -> float division"],
  ["float", 10.0,"float", 3.0, "10.0 / 3.0 -> float division"],
  ["int",   7,   "int",   2,   "7 / 2    -> 3 (integer division)"],
  ["int",   7,   "float", 2.0, "7 / 2.0  -> 3.5 (float division)"],
  ["int",   1,   "int",   3,   "1 / 3    -> 0 (integer division)"],
  ["int",   -7,  "int",   2,   "-7 / 2   -> -4 (integer division rounds toward negative)"],
  ["int",   0,   "int",   3,   "0 / 3    -> 0"],
]
# Division by zero is an inline-error case, so it needs render_errors: true.
div_zero_env = { "x" => 5 }
div_zero_tmpl = "{{ x | divided_by: 0 }}"
add(specs, "math_divided_by_int_by_zero",
    div_zero_tmpl, r(div_zero_tmpl, div_zero_env), 165,
    "divided_by quirk: 5 / 0 raises ZeroDivisionError which Liquid renders inline as 'Liquid error: divided by 0'. Requires render_errors: true.",
    env: div_zero_env, render_errors: true)
div_cases.each_with_index do |(ltype, lval, rtype, rval, label), i|
  env = { "x" => lval }
  tmpl = "{{ x | divided_by: #{rval.inspect} }}"
  out = r(tmpl, env)
  add(specs, "math_divided_by_int_vs_float_#{i}",
      tmpl, out, 160,
      "divided_by quirk: #{label}. Output #{out.inspect}.",
      env: env)
end

# ============================================================
# SECTION 3: unary ops, each input type
# ============================================================
UNARY.each do |op|
  TYPES.each do |label, val, typedesc|
    env = { "x" => val }
    tmpl = "{{ x | #{op} }}"
    out = r(tmpl, env)
    add(specs, "math_#{op}_#{label}",
        tmpl, out, 125,
        "#{op}: input = #{typedesc} -> #{out.inspect}.",
        env: env)
  end
end

# ============================================================
# SECTION 4: round with precision argument (the precision spectrum)
# ============================================================
round_cases = [
  [1.234, 2,   "positive precision rounds to N decimals"],
  [1.234, 1,   "precision 1"],
  [1.234, 0,   "precision 0 rounds to integer"],
  [1.234, nil, "no precision arg == precision 0"],
  [1.5,   nil, "0.5 rounds up to 2 (half-up)"],
  [-1.5,  nil, "-1.5 rounds to -2"],
  [1.234, -1,  "negative precision rounds to tens -> 0"],
  [15.0,  -1,  "15 with precision -1 -> 20 (rounds to nearest 10)"],
  [14.0,  -1,  "14 with precision -1 -> 10"],
  [5,     2,   "integer input with precision -> stays integer 5"],
  [0,     nil, "zero rounds to 0"],
  ["foo", nil, "non-numeric string round -> 0 (to_i = 0)"],
]
round_cases.each_with_index do |(val, prec, label), i|
  env = { "x" => val }
  tmpl = prec.nil? ? "{{ x | round }}" : "{{ x | round: #{prec} }}"
  out = r(tmpl, env)
  add(specs, "math_round_precision_#{i}",
      tmpl, out, 145,
      "round: #{label}. Input #{val.inspect}, precision #{prec.inspect} -> #{out.inspect}.",
      env: env)
end

# ============================================================
# SECTION 5: float result formatting (Ruby Float#to_s quirks)
# ============================================================
float_cases = [
  [10.0, 3,    "10.0 / 3 -> long float repr"],
  [1.0,  3,    "1.0 / 3"],
  [2.0,  3,    "2.0 / 3"],
  [1.0,  2,    "1.0 / 2 -> 0.5"],
]
float_cases.each_with_index do |(lval, rval, label), i|
  env = { "x" => lval }
  tmpl = "{{ x | divided_by: #{rval} }}"
  out = r(tmpl, env)
  add(specs, "math_float_repr_#{i}",
      tmpl, out, 150,
      "Float result formatting: #{label} -> #{out.inspect}. (Ruby Float#to_s.)",
      env: env)
end

# ============================================================
# SECTION 6: modulo sign and edge behavior
# ============================================================
mod_cases = [
  [5,   3,   "5 % 3 = 2"],
  [-5,  3,   "-5 % 3 (Ruby modulo follows divisor sign)"],
  [5,   -3,  "5 % -3"],
  [6,   3,   "6 % 3 = 0 (exact)"],
  [5,   1,   "5 % 1 = 0"],
  [0,   3,   "0 % 3 = 0"],
]
mod_cases.each_with_index do |(lval, rval, label), i|
  env = { "x" => lval }
  tmpl = "{{ x | modulo: #{rval} }}"
  out = r(tmpl, env)
  add(specs, "math_modulo_#{i}",
      tmpl, out, 140,
      "modulo: #{label} -> #{out.inspect}.",
      env: env)
end

# ============================================================
# Output YAML
# ============================================================
header = <<~HEADER
# Exhaustive math-filter type-coercion matrix spec for Liquid.
#
# The entire API surface of Liquid's math filters is part of the spec: every
# math operation (plus minus times divided_by modulo at_least at_most abs ceil
# floor round) applied to every input type (Integer Float numeric-String
# non-numeric-String nil true false empty-String Array). This locks down
# liquid-ruby's coercion rules: non-numeric/nil/bool/array values coerce to 0
# via to_i, and divided_by performs INTEGER division when both operands are
# integers (float division otherwise). Expected values were captured from the
# reference Shopify/liquid (liquid-ruby) implementation.
#
# Reference documentation:
#   Liquid math filters: https://shopify.dev/docs/api/liquid/filters#abs
#   Ruby Numeric coercion: https://ruby-doc.org/core/Numeric.html
---
_metadata:
  hint: |
    Liquid math filters coerce non-numeric operands via Ruby's to_i (and to_f
    for Float). The full coercion matrix is in scope: Integer, Float, numeric
    String, non-numeric String (-> 0), nil (-> 0), true/false (-> 0, NOT 1!),
    empty String (-> 0), Array (-> 0). KEY QUIRK: `divided_by` does INTEGER
    division when BOTH operands are integers (5/3 -> 1), and float division
    if either operand is a Float (5/3.0 -> 1.666...). `round` takes an optional
    precision (default 0; negative precision rounds to tens/hundreds).
    Reference: https://shopify.dev/docs/api/liquid/filters#abs
  doc: filters/math.md
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
  puts "  render_errors: #{s[:render_errors]}" if s.key?(:render_errors)
  puts "  expected: #{s[:expected].inspect}"
end
