#!/usr/bin/env ruby
# frozen_string_literal: true

# Lint: every filesystem entry in specs should have a recognizable
# template extension (.liquid, .svg, .json, etc.) or be a bare name
# that the filesystem resolver would add .liquid to.
#
# Bare names without extensions are ambiguous — they rely on the
# filesystem's default extension behavior. This check flags filesystem
# keys that have no extension so authors can decide whether to add one.
#
# Usage: ruby -Ilib scripts/verifiers/filesystem_extensions.rb
# Exit code is non-zero if any violation is found.

require "yaml"

SPEC_ROOT = File.expand_path("../../../specs", __dir__)

# Extensions that are valid in Liquid filesystems.
# .liquid is the standard; others appear in Shopify theme contexts.
VALID_EXTENSIONS = %w[.liquid .svg .json .css .js .scss .html .txt].freeze

module FilesystemExtensionVerifier
  class << self
    def run
      offenders = []

      Dir.glob(File.join(SPEC_ROOT, "**/*.yml")).sort.each do |file|
        next if File.basename(file) == "suite.yml"
        doc = YAML.unsafe_load(File.read(file)) rescue next
        specs = specs_of(doc)
        next unless specs.is_a?(Array)
        rel = file.sub("#{SPEC_ROOT}/", "")
        specs.each do |s|
          next unless s.is_a?(Hash)
          fs = s["filesystem"]
          next unless fs.is_a?(Hash)
          fs.each_key do |key|
            next if key.to_s == "_error-message" # special key, not a file
            next if key.to_s.end_with?(*VALID_EXTENSIONS)
            offenders << {
              file: rel,
              name: s["name"] || "(unnamed)",
              key: key.to_s,
            }
          end
        end
      end

      if offenders.empty?
        puts "OK: all filesystem entries have valid extensions."
        return 0
      end

      puts "Found #{offenders.size} filesystem entry(ies) without a recognized extension:\n\n"
      offenders.each do |o|
        puts "  #{o[:file]}: #{o[:name]}"
        puts "    key: #{o[:key].inspect} (expected one of: #{VALID_EXTENSIONS.join(", ")})"
      end
      puts
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

exit FilesystemExtensionVerifier.run if $PROGRAM_NAME == __FILE__
