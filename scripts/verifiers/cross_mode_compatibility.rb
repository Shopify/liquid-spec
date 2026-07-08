#!/usr/bin/env ruby
# frozen_string_literal: true

# Lint: specs that declare multiple error_modes (e.g. [lax, strict])
# must actually produce the same output in all declared modes when run
# against the reference liquid-ruby implementation.
#
# This catches specs that claim compatibility with a mode they don't
# actually work in. For example, a spec with error_mode: [lax, strict2]
# where the template actually fails to parse in strict2.
#
# Only specs with an array error_mode are checked — single-mode specs
# are already covered by the existing test run.
#
# Usage: ruby -Ilib scripts/verifiers/cross_mode_compatibility.rb
# Exit code is non-zero if any violation is found.

require "yaml"

LIQUID_LOADED = begin
  require "liquid"
  true
rescue LoadError
  false
end

module CrossModeCompatibilityVerifier
  class << self
    def run
      unless LIQUID_LOADED
        warn "WARNING: liquid gem not loaded — skipping cross-mode compatibility check"
        return 0
      end

      offenders = []
      each_spec do |spec|
        next unless spec[:error_mode].is_a?(Array)
        next unless spec[:template]

        env = spec[:environment] || {}
        # Skip specs with instantiate: (need class registry)
        next if env.to_s.include?("instantiate:")
        next if spec[:filesystem]
        next if spec[:template_factory]

        results = {}
        spec[:error_mode].each do |mode|
          results[mode] = run_template(spec[:template], env, mode)
        end

        # All modes should produce the same result (output or error)
        unique_results = results.values.uniq
        next if unique_results.size <= 1

        offenders << {
          file: spec[:file],
          line: spec[:line],
          name: spec[:name],
          modes: results.map { |m, r| "#{m}: #{r[0, 50]}" },
        }
      end

      if offenders.empty?
        puts "OK: all multi-mode specs produce consistent results across declared modes."
        return 0
      end

      puts "Found #{offenders.size} spec(s) with inconsistent results across declared modes:\n\n"
      offenders.each do |o|
        puts "  #{o[:file]}:#{o[:line]}  #{o[:name]}"
        o[:modes].each { |m| puts "    #{m}" }
        puts
      end
      1
    end

    private

    def run_template(template, env, mode)
      parsed = Liquid::Template.parse(template, error_mode: mode.to_sym)
      result = parsed.render(env)
      "OK: #{result.inspect[0, 50]}"
    rescue => e
      "ERROR: #{e.class.name.split('::').last}: #{e.message[0, 40]}"
    end

    def each_spec
      Dir.glob("specs/**/*.yml").sort.each do |file|
        doc = YAML.unsafe_load(File.read(file)) rescue next
        specs = specs_of(doc)
        next unless specs.is_a?(Array)
        name_lines = index_name_lines(file)
        specs.each_with_index do |s, i|
          next unless s.is_a?(Hash)
          em = s["error_mode"]
          next unless em.is_a?(Array)
          yield(
            file: file.sub("specs/", ""),
            line: name_lines[s["name"]],
            name: s["name"],
            template: s["template"],
            environment: s["environment"],
            filesystem: s["filesystem"],
            template_factory: s["template_factory"],
            error_mode: em
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

exit CrossModeCompatibilityVerifier.run if $PROGRAM_NAME == __FILE__
