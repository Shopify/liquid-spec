#!/usr/bin/env ruby
# frozen_string_literal: true

# Lint: specs that need lax mode must declare `error_mode: lax`.
#
# A spec is "lax-dependent" if it parse-fails in the default mode (strict2) but
# produces its expected output under lax. If it doesn't declare `error_mode: lax`
# (and doesn't expect a parse error via `errors:`), it is functionally broken:
# it runs in strict2 and fails for EVERY adapter, and it isn't auto-tagged
# `lax_parsing` so lax-opt-out adapters can't skip it either.
#
# This lint requires the reference `liquid` gem to parse/render templates.
#
# Usage: ruby -Ilib scripts/verify_lax_mode_declared.rb
# Exit non-zero if any violation is found.

require "yaml"
require "liquid"

module LaxModeDeclaredVerifier
  class << self
    def run
      offenders = []
      each_spec do |spec|
        next if spec[:lax_applied]               # file/suite already applies lax globally
        next if spec[:error_mode]                 # declares a mode already
        next if expects_parse_error?(spec)        # legitimately expects parse failure
        tmpl = spec[:template].to_s
        expected = spec[:expected]
        next if expected.nil?                     # no expected output to compare
        begin
          Liquid::Template.parse(tmpl, error_mode: :strict2)
          next                                    # parses in strict2 -> not lax-dependent
        rescue Liquid::SyntaxError, StandardError
          # strict2 rejects it -> check lax
        end
        begin
          actual = Liquid::Template.parse(tmpl, error_mode: :lax).render
          next unless actual == expected          # lax doesn't match -> different problem
        rescue StandardError
          next                                    # lax also fails -> different problem
        end
        offenders << spec
      end

      if offenders.empty?
        puts "OK: all lax-dependent specs declare error_mode: lax."
        return 0
      end

      puts "Found #{offenders.size} lax-dependent spec(s) missing `error_mode: lax`:\n\n"
      offenders.each do |o|
        puts "  #{o[:file]}:#{o[:line]}  #{o[:name]}"
        puts "    #{o[:template].to_s.gsub(/\n/, " ")[0, 80]}"
        puts "    fix: add `error_mode: lax` (auto-tags lax_parsing)\n\n"
      end
      1
    end

    private

    def expects_parse_error?(spec)
      errs = spec[:errors]
      return false unless errs.is_a?(Hash)
      errs.key?("parse_error") || errs.key?(:parse_error)
    end

    def each_spec
      Dir.glob("specs/**/*.yml").sort.each do |file|
        doc = YAML.unsafe_load(File.read(file)) rescue next
        specs = specs_of(doc)
        next unless specs.is_a?(Array)
        starts = index_block_starts(file)
        lax_applied = file_applies_lax?(file, doc)
        specs.each do |s|
          next unless s.is_a?(Hash)
          yield(
            file: file,
            line: starts[s["name"].to_s],
            name: s["name"],
            template: s["template"],
            expected: s["expected"],
            error_mode: s["error_mode"],
            errors: s["errors"],
            lax_applied: lax_applied
          )
        end
      end
    end

    # True if this file (or its suite) applies error_mode: lax globally, so
    # individual specs need not declare it.
    def file_applies_lax?(file, doc)
      meta = doc.is_a?(Hash) ? doc["_metadata"] : nil
      req = meta.is_a?(Hash) ? (meta["required_options"] || {}) : {}
      return true if req["error_mode"].to_s == "lax"
      suite_yml = File.join(File.dirname(file), "suite.yml")
      if File.file?(suite_yml)
        s = YAML.unsafe_load(File.read(suite_yml)) rescue nil
        defaults = s.is_a?(Hash) ? (s["defaults"] || {}) : {}
        return true if defaults["error_mode"].to_s == "lax"
      end
      false
    end

    def specs_of(d)
      return d if d.is_a?(Array)
      return d["specs"] || d["tests"] if d.is_a?(Hash)
      nil
    end

    def index_block_starts(file)
      map = {}
      lines = File.readlines(file)
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
  end
end

exit LaxModeDeclaredVerifier.run if $PROGRAM_NAME == __FILE__
