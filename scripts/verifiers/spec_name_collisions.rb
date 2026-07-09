#!/usr/bin/env ruby
# frozen_string_literal: true

# advisory: true
#
# Lint: no two specs may share the same name. Duplicate names cause one
# spec to shadow the other, making the hidden spec unreachable.
#
# Usage: ruby -Ilib scripts/verifiers/spec_name_collisions.rb
# Exit code is non-zero if any collision is found.

require "yaml"

SPEC_ROOT ||= File.expand_path("../../specs", __dir__)

module SpecNameCollisionVerifier
  class << self
    def run
      names = Hash.new { |h, k| h[k] = [] }

      Dir.glob(File.join(SPEC_ROOT, "**/*.yml")).sort.each do |file|
        next if File.basename(file) == "suite.yml"
        doc = YAML.unsafe_load(File.read(file)) rescue next
        specs = specs_of(doc)
        next unless specs.is_a?(Array)
        specs.each do |s|
          next unless s.is_a?(Hash) && s["name"]
          rel = file.sub("#{SPEC_ROOT}/", "")
          names[s["name"]] << rel
        end
      end

      collisions = names.select { |_, files| files.size > 1 }

      if collisions.empty?
        puts "OK: no spec name collisions found."
        return 0
      end

      puts "Found #{collisions.size} spec name collision(s):\n\n"
      collisions.each do |name, files|
        puts "  #{name}"
        files.each { |f| puts "    - #{f}" }
        puts
      end
      1
    end

    private

    def specs_of(doc)
      return doc if doc.is_a?(Array)
      return doc["specs"] || doc["tests"] if doc.is_a?(Hash)
      nil
    end
  end
end

exit SpecNameCollisionVerifier.run if $PROGRAM_NAME == __FILE__
