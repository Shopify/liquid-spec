#!/usr/bin/env ruby
# frozen_string_literal: true

# Lint: every spec that carries Ruby-specific content must declare a Ruby
# feature tag AND sit above complexity 100 (out of the beginner ramp).
#
# Ruby-specific content is anything a JSON/JS implementation cannot produce or
# receive faithfully without deliberately emulating Ruby semantics:
#   - expected output containing Ruby `Hash#inspect` notation (`=>` rocket,
#     or `:symbol` keys rendered as `{:foo=>...}`)
#   - an environment with a non-String Hash key (Symbol, Integer, Float,
#     Hash, Array, etc.) at any nesting depth — JSON object keys are strings
#   - expected output containing invalid-UTF-8 bytes (binary data)
#
# A spec matching any of these must:
#   1. list at least one Ruby feature tag
#      (ruby_types / ruby_drops / binary_data / runtime_drops / template_factory)
#   2. have complexity > 100
#
# Usage: ruby -Ilib scripts/verify_ruby_type_tags.rb
# Exit code is non-zero if any violation is found.

require "yaml"

RUBY_FEATURES = %w[ruby_types ruby_drops binary_data runtime_drops template_factory].freeze
COMPLEXITY_FLOOR = 100

# Standard test drops — portable, not Ruby-specific.
# These are documented in docs/test_drops.md and can be implemented
# natively by any Liquid implementation without Ruby runtime.
STANDARD_DROPS = %w[
  BooleanDrop NumberDrop StringDrop
  MethodDrop IndexDrop SequenceDrop
  NilDrop OpaqueDrop ErrorDrop
].freeze

module RubyTypeTagVerifier
  class << self
    def run
      offenders = []
      each_spec do |spec|
        markers = detect_markers(spec)
        next if markers.empty?
        reasons = []
        feats = spec[:features] || []
        unless (feats & RUBY_FEATURES).any?
          reasons << "missing ruby feature tag (needs one of: #{RUBY_FEATURES.join(", ")})"
        end
        c = spec[:complexity]
        if c && c <= COMPLEXITY_FLOOR
          reasons << "complexity #{c} <= #{COMPLEXITY_FLOOR} (Ruby-quirk specs belong above the beginner ramp)"
        end
        next if reasons.empty?
        offenders << {
          file: spec[:file],
          line: spec[:line],
          name: spec[:name],
          markers: markers,
          reasons: reasons,
        }
      end

      if offenders.empty?
        puts "OK: all Ruby-content specs are tagged and above complexity #{COMPLEXITY_FLOOR}."
        return 0
      end

      puts "Found #{offenders.size} spec(s) with Ruby-specific content that violate the rules:\n\n"
      offenders.each do |o|
        puts "  #{o[:file]}:#{o[:line]}  #{o[:name]}"
        puts "    markers: #{o[:markers].join(", ")}"
        o[:reasons].each { |r| puts "    - #{r}" }
        puts
      end
      1
    end

    private

    # Yield a hash for every spec across all spec files:
    # { file, line, name, expected, environment, features, complexity }
    def each_spec
      Dir.glob("specs/**/*.yml").sort.each do |file|
        doc = YAML.unsafe_load(File.read(file)) rescue next
        specs = specs_of(doc)
        next unless specs.is_a?(Array)
        # line numbers: scan the raw file for "- name:" anchors
        name_lines = index_name_lines(file)
        specs.each_with_index do |s, i|
          next unless s.is_a?(Hash)
          yield(
            file: file,
            line: name_lines[s["name"]],
            name: s["name"],
            expected: s["expected"],
            environment: s["environment"],
            features: (s["features"] || []).map(&:to_s),
            complexity: s["complexity"],
          )
        end
      end
    end

    def specs_of(doc)
      return doc if doc.is_a?(Array)
      return doc["specs"] || doc["tests"] if doc.is_a?(Hash)
      nil
    end

    # name -> first line number (1-based) of the spec block containing it.
    # Handles both formats: blocks starting with `- name:` and blocks where
    # `name:` is a later field (e.g. `- template:` first).
    def index_name_lines(file)
      map = {}
      lines = File.readlines(file)
      # block starts: any list-item mapping opener ("- <key>:")
      starts = lines.each_index.select { |i| lines[i] =~ /^- [A-Za-z]/ }
      starts.each_with_index do |st, k|
        en = (k + 1 < starts.size) ? starts[k + 1] : lines.size
        (st...en).each do |i|
          if lines[i] =~ /^  name:\s*(.+?)\s*$/
            map[$1] = st + 1 unless map.key?($1)
            break
          end
        end
      end
      map
    end

    def detect_markers(spec)
      markers = []
      exp = spec[:expected]
      markers << "hash-inspect (=>)" if exp.is_a?(String) && exp.include?("=>")
      markers << "symbol-inspect (:sym)" if exp.is_a?(String) && exp.match?(/[{:]\s*:[a-z_][a-z0-9_]*[=>,}]/)
      if exp.is_a?(String) && exp.bytes.any? { |b| b > 127 } && !exp.dup.force_encoding("UTF-8").valid_encoding?
        markers << "invalid-utf8 (binary)"
      end
      env = spec[:environment]
      markers.concat(non_string_key_markers(env, 0)) if env
      markers.concat(instantiate_markers(env, 0)) if env
      markers.uniq
    end

    # Walk a value looking for Hashes whose keys are not all Strings.
    def non_string_key_markers(obj, depth)
      return [] if depth > 40
      case obj
      when Hash
        out = []
        weird = obj.keys.reject { |k| k.is_a?(String) }
        weird.group_by { |k| k.class }.each do |klass, keys|
          out << "non-string hash key (#{klass}; #{keys.size})"
        end
        obj.values.each { |v| out.concat(non_string_key_markers(v, depth + 1)) }
        out
      when Array
        obj.flat_map { |e| non_string_key_markers(e, depth + 1) }
      else
        []
      end
    end

    # Walk a value looking for instantiate: patterns that create Ruby drops.
    # Two forms: string "instantiate:ClassName" or hash key "instantiate:ClassName".
    def instantiate_markers(obj, depth)
      return [] if depth > 40
      case obj
      when Hash
        out = []
        obj.each do |k, v|
          if k.is_a?(String) && k.start_with?("instantiate:")
            class_name = k.sub("instantiate:", "").chomp(":")
            # Skip standard test drops — they're portable, not Ruby-specific
            out << "instantiate: drop (#{class_name})" unless STANDARD_DROPS.include?(class_name)
          end
          out.concat(instantiate_markers(v, depth + 1))
        end
        out
      when Array
        obj.flat_map { |e| instantiate_markers(e, depth + 1) }
      when String
        if obj.start_with?("instantiate:")
          class_name = obj.sub("instantiate:", "").split(/\.|\z/).first
          STANDARD_DROPS.include?(class_name) ? [] : [ "instantiate: drop (#{class_name})" ]
        else
          []
        end
      else
        []
      end
    end
  end
end

exit RubyTypeTagVerifier.run if $PROGRAM_NAME == __FILE__
