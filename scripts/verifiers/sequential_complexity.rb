#!/usr/bin/env ruby
# frozen_string_literal: true

# Curated curriculum files can opt into a strict one-lesson-per-level sequence
# with `_metadata.sequential_complexity: true`. Every following spec must use
# the next integer complexity. Generated breadth should not opt in.

require "yaml"

SPEC_ROOT ||= File.expand_path("../../specs", __dir__)

module SequentialComplexityVerifier
  class << self
    def run
      offenders = []

      Dir.glob(File.join(SPEC_ROOT, "**/*.yml")).sort.each do |file|
        next if File.basename(file) == "suite.yml"

        doc = YAML.unsafe_load_file(file)
        next unless doc.is_a?(Hash)
        next unless doc.dig("_metadata", "sequential_complexity") == true

        specs = doc["specs"]
        unless specs.is_a?(Array) && !specs.empty?
          offenders << "#{relative(file)}: sequential curriculum has no specs"
          next
        end

        specs.each_cons(2) do |previous, current|
          expected = previous["complexity"].to_i + 1
          actual = current["complexity"]
          next if actual == expected

          offenders << "#{relative(file)}: #{current["name"]} has complexity #{actual.inspect}; " \
            "expected #{expected} after #{previous["name"]}"
        end
      rescue Psych::Exception => error
        offenders << "#{relative(file)}: YAML error: #{error.message}"
      end

      if offenders.empty?
        puts "OK: sequential curriculum files advance one complexity level per spec."
        return 0
      end

      puts "Sequential curriculum violations:\n\n#{offenders.join("\n")}"
      1
    end

    private

    def relative(file)
      file.sub("#{SPEC_ROOT}/", "")
    end
  end
end

exit SequentialComplexityVerifier.run if $PROGRAM_NAME == __FILE__
