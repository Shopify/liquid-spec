#!/usr/bin/env ruby
# frozen_string_literal: true

# Move specs matching a pattern from one YAML file to another
#
# Usage: ruby scripts/move_spec.rb -n /pattern/ from_file to_file
#
# Examples:
#   ruby scripts/move_spec.rb -n /ParsingQuirksTest/ specs/liquid_ruby/specs.yml specs/liquid_ruby_lax/specs.yml
#   ruby scripts/move_spec.rb -n "test_float" specs/liquid_ruby/specs.yml specs/liquid_ruby_lax/specs.yml

require "optparse"

def parse_specs(content)
  # Parse YAML file into individual spec entries (text-based)
  # Each spec starts with "- name:" at column 0
  specs = []
  current_spec = []
  header_lines = []
  in_header = true

  content.each_line do |line|
    if line.start_with?("- name:")
      in_header = false
      specs << current_spec.join unless current_spec.empty?
      current_spec = [line]
    elsif in_header
      header_lines << line unless line.strip == "---"
    else
      current_spec << line
    end
  end
  specs << current_spec.join unless current_spec.empty?

  [header_lines.join, specs]
end

def spec_name(spec_text)
  if spec_text =~ /^- name:\s*(.+)$/
    $1.strip
  else
    nil
  end
end

def parse_pattern(pattern_str)
  if pattern_str =~ %r{\A/(.+)/([imx]*)\z}
    regex_str = $1
    flags = $2
    options = 0
    options |= Regexp::IGNORECASE if flags.include?("i")
    options |= Regexp::MULTILINE if flags.include?("m")
    options |= Regexp::EXTENDED if flags.include?("x")
    Regexp.new(regex_str, options)
  else
    # Plain string: case-insensitive substring match
    Regexp.new(Regexp.escape(pattern_str), Regexp::IGNORECASE)
  end
end

# Parse command line options
options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} -n PATTERN from_file to_file"

  opts.on("-n", "--name PATTERN", "Pattern to match spec names (use /regex/ for regex)") do |p|
    options[:pattern] = p
  end

  opts.on("--dry-run", "Show what would be moved without making changes") do
    options[:dry_run] = true
  end

  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end

parser.parse!

unless options[:pattern]
  $stderr.puts "Error: -n PATTERN is required"
  $stderr.puts parser
  exit 1
end

if ARGV.size != 2
  $stderr.puts "Error: Expected from_file and to_file arguments"
  $stderr.puts parser
  exit 1
end

from_file = ARGV[0]
to_file = ARGV[1]

unless File.exist?(from_file)
  $stderr.puts "Error: Source file not found: #{from_file}"
  exit 1
end

pattern = parse_pattern(options[:pattern])

# Read source file
from_content = File.read(from_file)
from_header, from_specs = parse_specs(from_content)

# Find matching specs
matching_specs = []
remaining_specs = []

from_specs.each do |spec_text|
  name = spec_name(spec_text)
  if name && name =~ pattern
    matching_specs << spec_text
  else
    remaining_specs << spec_text
  end
end

if matching_specs.empty?
  puts "No specs matching #{pattern.inspect} found in #{from_file}"
  exit 0
end

puts "Found #{matching_specs.size} specs matching #{pattern.inspect}:"
matching_specs.each do |spec_text|
  puts "  - #{spec_name(spec_text)}"
end

if options[:dry_run]
  puts "\nDry run - no changes made"
  exit 0
end

# Read or create destination file
if File.exist?(to_file)
  to_content = File.read(to_file)
  to_header, to_specs = parse_specs(to_content)
else
  to_header = ""
  to_specs = []
end

# Add matching specs to destination
to_specs.concat(matching_specs)

# Write updated files
puts "\nMoving specs..."

# Write source file (without matching specs)
File.write(from_file, "---\n#{from_header}#{remaining_specs.join}")
puts "  Updated #{from_file} (#{remaining_specs.size} specs remaining)"

# Write destination file (with added specs)
File.write(to_file, "---\n#{to_header}#{to_specs.join}")
puts "  Updated #{to_file} (#{to_specs.size} specs total)"

puts "\nDone! Moved #{matching_specs.size} specs from #{from_file} to #{to_file}"
