#!/usr/bin/env ruby
# frozen_string_literal: true

# This script converts specs with exact error message expectations to use
# flexible pattern matching via the `errors` field.
#
# Usage:
#   ruby scripts/normalize_error_specs.rb specs/shopify_production_recordings/recorded_specs.yml
#   ruby scripts/normalize_error_specs.rb specs/shopify_production_recordings/recorded_specs.yml --dry-run
#   ruby scripts/normalize_error_specs.rb specs/shopify_production_recordings/recorded_specs.yml --verbose

require "yaml"
require "fileutils"

# Load liquid and test drops for YAML parsing
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "liquid"
require "liquid/spec/test_drops"
require "liquid/spec/yaml_initializer"

# Patterns that indicate an error message in expected output
ERROR_PATTERNS = [
  /\ALiquid error \(line \d+\):/i,
  /\ALiquid syntax error/i,
  /\AERROR:/,
].freeze

# Parse error message into components
# Returns: { type: :parse_error|:render_error, line: N, message: "..." }
def parse_error_message(expected)
  case expected
  when /\ALiquid syntax error \(line (\d+)\): (.+)\z/i
    { type: :parse_error, line: Regexp.last_match(1).to_i, message: Regexp.last_match(2).strip }
  when /\ALiquid error \(line (\d+)\): (.+)\z/i
    { type: :render_error, line: Regexp.last_match(1).to_i, message: Regexp.last_match(2).strip }
  when /\AERROR: (\w+(?:::\w+)*): (.+)\z/
    # ERROR: Liquid::SyntaxError: Liquid syntax error (line 1): ...
    { type: :exception, class: Regexp.last_match(1), message: Regexp.last_match(2).strip }
  end
end

# Generate a flexible regex pattern from an error message
def generate_pattern(message)
  # Extract the core message, removing implementation-specific suffixes
  # e.g., 'Syntax error in tag "render" - Template name must be a quoted string in "name"'
  #   -> 'template name must be a quoted string'

  core = message.dup

  # Remove trailing context like ' in "..."'
  core = core.sub(/\s+in\s+"[^"]*"\s*\z/i, "")

  # Remove leading prefixes like "Syntax error in tag 'render' -"
  core = core.sub(/\ASyntax error in tag ['"][^'"]+['"]\s*-?\s*/i, "")

  # Remove leading "Expected X but found Y in" pattern
  core = core.sub(/\AExpected \w+ but found \w+ in\s*/i, "")

  # Remove "Unexpected character X in" pattern - keep just the character
  if core =~ /\AUnexpected character (\S+)/i
    core = "unexpected character"
  end

  # For "Unknown operator X" - keep generic
  if core =~ /\AUnknown operator/i
    core = "unknown operator"
  end

  # For "comparison of X with Y failed" - keep generic
  if core =~ /\Acomparison of \S+ with \S+ failed/i
    core = "comparison .* failed"
  end

  # For "wrong number of arguments" - keep generic
  if core =~ /\Awrong number of arguments/i
    core = "wrong number of arguments"
  end

  # For "Could not find asset X" - keep the asset name but make it case insensitive
  if core =~ /\ACould not find asset (\S+)/i
    asset = Regexp.last_match(1).downcase
    core = "could not find asset.*#{Regexp.escape(asset)}"
  end

  # For "invalid integer X" - keep generic or specific?
  # Keep specific for now since the integer value matters for the test

  # For class names like TestDrops::... - generalize
  core = core.gsub(/TestDrops::\S+/i, ".*")

  # Clean up and downcase for case-insensitive matching
  core.strip.downcase
end

# Check if expected looks like a pure error message (no other content)
def pure_error?(expected)
  return false unless expected.is_a?(String)

  # Check if it matches known error patterns
  ERROR_PATTERNS.any? { |p| expected.match?(p) }
end

# Check if expected contains an embedded error (content + error)
def embedded_error?(expected)
  return false unless expected.is_a?(String)

  # Contains "Liquid error (line N):" somewhere but has other content
  expected.include?("Liquid error") && !pure_error?(expected)
end

def process_spec(spec, verbose: false)
  expected = spec["expected"]
  return unless expected.is_a?(String)

  # Skip if already using errors field
  return if spec["errors"]

  if pure_error?(expected)
    parsed = parse_error_message(expected)
    return unless parsed

    pattern = generate_pattern(parsed[:message])
    return if pattern.empty?

    puts "  Converting: #{expected[0..60]}..." if verbose
    puts "    -> pattern: #{pattern}" if verbose

    # Determine error type
    error_type = case parsed[:type]
    when :parse_error, :exception then "parse_error"
    when :render_error then "output" # render errors appear in output
    else "output"
    end

    {
      "errors" => { error_type => [pattern] },
      "expected" => nil, # Remove expected since we're using errors
    }
  elsif embedded_error?(expected)
    # For embedded errors, we use output patterns instead
    # Extract just the error part
    if expected =~ /(Liquid error \(line \d+\): [^,]+)/
      error_part = Regexp.last_match(1)
      pattern = generate_pattern(error_part.sub(/\ALiquid error \(line \d+\): /, ""))

      puts "  Embedded error: #{expected[0..60]}..." if verbose
      puts "    -> output pattern: #{pattern}" if verbose

      # Keep expected but add output pattern for the error part
      {
        "errors" => { "output" => [pattern] },
        # Keep expected as-is for now - we'll handle this differently
      }
    end
  else
    nil
  end
end

def process_file(path, dry_run: false, verbose: false)
  puts "Processing: #{path}"

  content = File.read(path)
  data = YAML.unsafe_load(content)

  # Handle both array format and hash format with _metadata
  specs = if data.is_a?(Array)
    data
  elsif data.is_a?(Hash) && data["specs"]
    data["specs"]
  else
    puts "  Unknown format, skipping"
    return
  end

  modified_count = 0

  specs.each do |spec|
    changes = process_spec(spec, verbose: verbose)
    next unless changes

    modified_count += 1

    unless dry_run
      # Apply changes
      changes.each do |key, value|
        if value.nil?
          spec.delete(key)
        else
          spec[key] = value
        end
      end
    end
  end

  puts "  Modified: #{modified_count} specs"

  unless dry_run || modified_count == 0
    # Write back
    File.write(path, YAML.dump(data))
    puts "  Saved!"
  end
end

# Main
if ARGV.empty?
  puts "Usage: #{$0} <spec_file.yml> [--dry-run] [--verbose]"
  puts ""
  puts "Converts specs with exact error message expectations to use flexible"
  puts "pattern matching via the `errors` field."
  exit 1
end

files = ARGV.reject { |a| a.start_with?("--") }
dry_run = ARGV.include?("--dry-run")
verbose = ARGV.include?("--verbose") || ARGV.include?("-v")

puts "DRY RUN - no changes will be made" if dry_run
puts ""

files.each do |file|
  process_file(file, dry_run: dry_run, verbose: verbose)
end
