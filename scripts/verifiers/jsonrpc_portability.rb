#!/usr/bin/env ruby
# frozen_string_literal: true

# Lint: no spec without a ruby feature tag should produce an RPC drop
# command over JSON-RPC.
#
# DropProxy.wrap sends _rpc_drop markers for any environment value that is
# not a JSON primitive (nil, true, false, Integer, Float, String, Hash,
# Array) and not a standard test drop. YAML auto-parses timestamp strings
# into Time objects, :symbols into Symbol objects, etc. — these are
# invisible at the YAML text level but become RPC drops at runtime.
#
# This verifier parses each spec's YAML the same way the spec loader does,
# then walks the environment looking for non-primitive values that would
# trigger RPC wrapping. Any such spec must declare ruby_types or ruby_drops
# so non-Ruby adapters skip it.
#
# Usage: ruby -Ilib scripts/verifiers/jsonrpc_portability.rb
# Exit code is non-zero if any violation is found.

require "yaml"
RUBY_FEATURES = %w[ruby_types ruby_drops].freeze
# Types that JSON can represent natively — no RPC wrapping needed.
JSON_PRIMITIVES = [NilClass, TrueClass, FalseClass, Integer, Float, String].freeze

# Non-primitive Ruby types that DropProxy.wrap explicitly converts to
# portable representations (ISO 8601 strings), so they do NOT trigger
# RPC drops. If a new type is added to DropProxy.wrap's portable path,
# add it here so the verifier stays in sync.
PORTABLE_RUBY_TYPES = [Time, Date, DateTime].freeze


module JsonRpcPortabilityVerifier
  class << self
    def run
      offenders = []
      each_spec do |spec|
        markers = non_primitive_markers(spec[:environment], 0)
        next if markers.empty?

        feats = spec[:features] || []
        unless (feats & RUBY_FEATURES).any?
          offenders << {
            file: spec[:file],
            line: spec[:line],
            name: spec[:name],
            markers: markers.uniq,
          }
        end
      end

      if offenders.empty?
        puts "OK: no untagged specs produce RPC drops over JSON-RPC."
        return 0
      end

      puts "Found #{offenders.size} spec(s) with non-primitive environment values" \
             " that would trigger RPC drops without a ruby feature tag:\n\n"
      offenders.each do |o|
        puts "  #{o[:file]}:#{o[:line]}  #{o[:name]}"
        o[:markers].each { |m| puts "    - #{m}" }
        puts "    fix: add features: [ruby_types] or [ruby_drops]"
        puts
      end
      1
    end

    private

    # Yield a hash for every spec across all spec files.
    def each_spec
      Dir.glob("specs/**/*.yml").sort.each do |file|
        doc = YAML.unsafe_load(File.read(file, encoding: Encoding::UTF_8)) rescue next
        specs = specs_of(doc)
        next unless specs.is_a?(Array)
        name_lines = index_name_lines(file)
        specs.each_with_index do |s, i|
          next unless s.is_a?(Hash)
          yield(
            file: file,
            line: name_lines[s["name"]],
            name: s["name"],
            environment: s["environment"],
            features: (s["features"] || []).map(&:to_s)
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
    def index_name_lines(file)
      map = {}
      lines = File.readlines(file, encoding: Encoding::UTF_8)
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

    # Walk a parsed YAML value looking for non-primitive leaf types that
    # would trigger _rpc_drop over JSON-RPC. Hashes and Arrays are JSON
    # containers; their contents are checked recursively. Types in
    # PORTABLE_RUBY_TYPES (Time, Date, DateTime) are explicitly handled
    # by DropProxy.wrap as ISO 8601 strings, so they don't trigger RPC.
    # Anything else (Symbol, Rational, custom objects, etc.) would.
    def non_primitive_markers(obj, depth)
      return [] if depth > 40
      case obj
      when *JSON_PRIMITIVES
        []
      when *PORTABLE_RUBY_TYPES
        []
      when Hash
        obj.values.flat_map { |v| non_primitive_markers(v, depth + 1) }
      when Array
        obj.flat_map { |e| non_primitive_markers(e, depth + 1) }
      else
        ["non-primitive type #{obj.class} (would become _rpc_drop over JSON-RPC)"]
      end
    end
  end
end

exit JsonRpcPortabilityVerifier.run if $PROGRAM_NAME == __FILE__
