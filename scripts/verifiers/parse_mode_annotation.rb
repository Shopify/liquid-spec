#!/usr/bin/env ruby
# frozen_string_literal: true

# Lint: every spec that produces different results in different parse modes
# must declare an explicit error_mode. Specs without error_mode are assumed
# to work identically in lax, strict, and strict2 — if they don't, they need
# an annotation.
#
# This catches the "lack of implicit parse strictness annotation" problem:
# a spec that relies on strict-mode rejection or lax-mode recovery but
# doesn't declare error_mode will silently fail when an adapter uses a
# different default mode.
#
# Only specs with NO error_mode are checked. Specs with error_mode are
# assumed to have consciously chosen their mode.
#
# Usage: ruby -Ilib scripts/verifiers/parse_mode_annotation.rb
# Exit code is non-zero if any violation is found.

require "yaml"

LIQUID_LOADED = begin
  require "liquid"
  true
rescue LoadError
  false
end

module ParseModeAnnotationVerifier
  class << self
    def run
      unless LIQUID_LOADED
        warn "WARNING: liquid gem not loaded — skipping parse mode annotation check"
        return 0
      end

      offenders = []
      each_spec do |spec|
        # Only check specs with NO error_mode — they must work in all modes
        next if spec[:error_mode]
        next unless spec[:template]
        # Skip specs in lax suite — they inherit error_mode: lax from suite.yml
        next if spec[:file]&.start_with?("liquid_ruby_lax/")

        # Check 1: any spec with errors: (parse_error or render_error) must
        # declare error_mode. Syntax errors are mode-dependent — a parse
        # error in strict mode may be recovered in lax mode. Without an
        # explicit error_mode, the adapter doesn't know which mode to use.
        if spec[:errors] && spec[:errors].any?
          offenders << {
            file: spec[:file],
            line: spec[:line],
            name: spec[:name],
            template: spec[:template][0, 60],
            reason: "has errors: but no error_mode — syntax errors are mode-dependent",
          }
          next
        end

        # Check 2: for specs without errors:, run the template in all three
        # modes. If the output differs, the spec needs an error_mode.
        env = spec[:environment] || {}
        next if env.to_s.include?("instantiate:")
        next if spec[:filesystem]
        next if spec[:template_factory]
        next if spec[:generate]
        # Skip increment/decrement — state leaks across modes in same process
        next if spec[:template]&.include?("increment") || spec[:template]&.include?("decrement")

        results = {}
        [:lax, :strict, :strict2].each do |mode|
          results[mode] = run_template(spec[:template], env, mode)
        end

        unique = results.values.uniq
        next if unique.size <= 1

        offenders << {
          file: spec[:file],
          line: spec[:line],
          name: spec[:name],
          template: spec[:template][0, 60],
          reason: "produces different output across parse modes",
          lax: results[:lax][0, 40],
          strict: results[:strict][0, 40],
          strict2: results[:strict2][0, 40],
        }
      end

      if offenders.empty?
        puts "OK: all unannotated specs produce consistent results across parse modes."
        return 0
      end

      puts "Found #{offenders.size} spec(s) without error_mode that need annotation:\n\n"
      offenders.each do |o|
        puts "  #{o[:file]}:#{o[:line]}  #{o[:name]}"
        puts "    template: #{o[:template]}"
        puts "    - #{o[:reason]}"
        if o[:lax]
          puts "    lax:      #{o[:lax]}"
          puts "    strict:   #{o[:strict]}"
          puts "    strict2:  #{o[:strict2]}"
        end
        puts
      end
      1
    end

    private

    def run_template(template, env, mode)
      parsed = Liquid::Template.parse(template, error_mode: mode)
      result = parsed.render(env)
      "OK: #{result.inspect[0, 40]}"
    rescue => e
      "ERROR: #{e.class.name.split('::').last}"
    end

    def each_spec
      # Build map of directory → suite-level default error_mode
      suite_modes = {}
      Dir.glob("specs/**/suite.yml").sort.each do |sf|
        doc = YAML.unsafe_load(File.read(sf)) rescue next
        next unless doc.is_a?(Hash)
        mode = doc.dig("defaults", "error_mode")
        dir = File.dirname(sf).sub("specs/", "")
        suite_modes[dir] = mode if mode
      end

      Dir.glob("specs/**/*.yml").sort.each do |file|
        next if File.basename(file) == "suite.yml"
        doc = YAML.unsafe_load(File.read(file)) rescue next
        specs = specs_of(doc)
        next unless specs.is_a?(Array)
        meta_opts = doc.is_a?(Hash) ? (doc["_metadata"] || {}) : {}
        meta_mode = meta_opts.dig("required_options", "error_mode")
        # Find suite-level default for this file's directory
        dir = File.dirname(file).sub("specs/", "")
        suite_mode = suite_modes[dir]
        name_lines = index_name_lines(file)
        specs.each_with_index do |s, i|
          next unless s.is_a?(Hash)
          spec_mode = s["error_mode"] || meta_mode || suite_mode
          yield(
            file: file.sub("specs/", ""),
            line: name_lines[s["name"]],
            name: s["name"],
            template: s["template"],
            environment: s["environment"],
            filesystem: s["filesystem"],
            template_factory: s["template_factory"],
            errors: s["errors"],
            generate: s["generate"],
            error_mode: spec_mode
          )
        end
      end
    end

    def specs_of(doc)
      return doc if doc.is_a?(Array)
      return doc["specs"] || doc["tests"] if doc.is_a?(Hash)
      nil
    end

    def index_name_lines(file)
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

exit ParseModeAnnotationVerifier.run if $PROGRAM_NAME == __FILE__
