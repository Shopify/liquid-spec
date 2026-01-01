#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to extract lax-mode-only specs into separate YAML files
#
# Usage: ruby scripts/extract_lax_specs.rb
#
# This will:
# 1. Read each YAML spec file in specs/liquid_ruby/
# 2. Extract specs with error_mode: :lax into a new *_lax.yml file
# 3. Remove lax specs from the original file
#
# Uses text-based parsing to preserve Ruby object references in YAML

require "fileutils"

SPECS_DIR = File.expand_path("../specs/liquid_ruby", __dir__)

# Parse YAML file into individual spec entries (text-based)
# Each spec starts with "- name:" at column 0
def parse_specs(content)
  specs = []
  current_spec = []

  content.each_line do |line|
    if line.start_with?("- name:")
      specs << current_spec.join unless current_spec.empty?
      current_spec = [line]
    elsif line.start_with?("---")
      # Skip YAML document start
      next
    else
      current_spec << line
    end
  end
  specs << current_spec.join unless current_spec.empty?

  specs
end

def spec_is_lax?(spec_text)
  spec_text.include?("error_mode: :lax")
end

def process_yaml_file(filepath)
  return unless File.exist?(filepath)
  return if filepath.end_with?("_lax.yml") # Skip already-extracted lax files

  filename = File.basename(filepath)
  puts "Processing #{filename}..."

  content = File.read(filepath)
  specs = parse_specs(content)

  if specs.empty?
    puts "  No specs found, skipping"
    return
  end

  lax_specs = []
  strict_specs = []

  specs.each do |spec_text|
    if spec_is_lax?(spec_text)
      lax_specs << spec_text
    else
      strict_specs << spec_text
    end
  end

  if lax_specs.empty?
    puts "  No lax specs found, skipping"
    return
  end

  puts "  Found #{lax_specs.length} lax specs, #{strict_specs.length} strict/default specs"

  # Write lax specs to new file
  base_name = File.basename(filepath, ".yml")
  lax_filepath = File.join(File.dirname(filepath), "#{base_name}_lax.yml")

  File.write(lax_filepath, "---\n" + lax_specs.join)
  puts "  Wrote #{lax_specs.length} specs to #{File.basename(lax_filepath)}"

  # Update original file with only strict specs
  File.write(filepath, "---\n" + strict_specs.join)
  puts "  Updated #{filename} with #{strict_specs.length} specs"
end

# Find all YAML files in specs/liquid_ruby/
yaml_files = Dir.glob(File.join(SPECS_DIR, "*.yml"))

yaml_files.each do |filepath|
  process_yaml_file(filepath)
end

puts "\nDone!"
