#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifier: spec YAML structure / well-formedness
#
# Checks every spec YAML file for:
# - Valid YAML (parses without error)
# - Correct top-level structure (array or hash with specs: key)
# - Every spec has required fields (name, template)
# - complexity (if present) is an integer in 1..1000
# - features (if present) are from the known set
# - error_mode (if present) is one of :strict, :strict2, :lax
# - environment/filesystem (if present) are hashes
#
# Usage: ruby -Ilib scripts/verifiers/spec_schema.rb
# Exit code is non-zero if any violation is found.

require "yaml"

VALID_FEATURES = %w[
  core inline_errors ruby_types lax_parsing strict_parsing
  shopify_tags shopify_objects shopify_filters shopify_error_handling
  shopify_blank shopify_string_access shopify_error_format shopify_includes
  ruby_drops drop_class_output template_factory binary_data
  strict2_blank_body_errors drops randomness shopify_resource_limits
].freeze

VALID_ERROR_MODES = %w[strict strict2 lax].freeze

SPEC_ROOT = File.expand_path("../../../specs", __dir__)

module SpecSchemaVerifier
  class << self
    def run
      offenders = []

      spec_files.each do |file|
        rel = relative_path(file)
        data = safe_load(file)
        if data.nil?
          offenders << { file: rel, line: 0, name: "(file)", issues: ["YAML parse failed or file is empty"] }
          next
        end

        specs = extract_specs(data)
        if specs.nil?
          offenders << { file: rel, line: 0, name: "(file)", issues: ["invalid top-level structure: expected array or hash with 'specs:' key"] }
          next
        end

        specs.each_with_index do |spec, idx|
          next unless spec.is_a?(Hash)
          issues = check_spec(spec)
          next if issues.empty?
          offenders << { file: rel, line: idx + 1, name: spec["name"] || "(spec ##{idx + 1})", issues: issues }
        end
      end

      if offenders.empty?
        puts "OK: all spec YAML files are well-formed."
        return 0
      end

      puts "Found #{offenders.size} spec(s) with structural issues:\n\n"
      offenders.each do |o|
        puts "  #{o[:file]}:#{o[:line]}  #{o[:name]}"
        o[:issues].each { |i| puts "    - #{i}" }
        puts
      end
      1
    end

    private

    def spec_files
      Dir.glob(File.join(SPEC_ROOT, "**/*.yml")).sort
    end

    def relative_path(path)
      path.sub("#{SPEC_ROOT}/", "")
    end

    def safe_load(file)
      YAML.unsafe_load(File.read(file))
    rescue => e
      nil
    end

    def extract_specs(data)
      case data
      when Array
        data
      when Hash
        data["specs"]
      else
        nil
      end
    end

    def check_spec(spec)
      issues = []

      # Required: name
      unless spec["name"].is_a?(String) && !spec["name"].empty?
        issues << "missing or empty 'name'"
      end

      # Required: template
      unless spec["template"].is_a?(String)
        issues << "missing 'template' (must be a string)"
      end

      # complexity: integer 1..1000 if present
      c = spec["complexity"]
      if c && (!c.is_a?(Integer) || c < 1 || c > 1000)
        issues << "complexity #{c.inspect} is not an integer in 1..1000"
      end

      # features: array of known feature names if present
      f = spec["features"]
      if f
        unless f.is_a?(Array)
          issues << "features must be an array, got #{f.class}"
        else
          f.each do |feat|
            feat_str = feat.to_s
            unless VALID_FEATURES.include?(feat_str)
              issues << "unknown feature tag '#{feat_str}' (valid: #{VALID_FEATURES.join(", ")})"
            end
          end
        end
      end

      # error_mode: one of strict/strict2/lax if present.
      # Can be a single value or an array of compatible modes.
      em = spec["error_mode"]
      if em
        modes = em.is_a?(Array) ? em : [em]
        modes.each do |m|
          if !VALID_ERROR_MODES.include?(m.to_s)
            issues << "error_mode '#{m}' is not one of #{VALID_ERROR_MODES.join(", ")}"
          end
        end
      end

      # environment: hash if present
      env = spec["environment"]
      if env && !env.is_a?(Hash)
        issues << "environment must be a hash, got #{env.class}"
      end

      # filesystem: hash if present
      fs = spec["filesystem"]
      if fs && !fs.is_a?(Hash)
        issues << "filesystem must be a hash, got #{fs.class}"
      end

      # Must have either expected or errors (but not both)
      has_expected = spec.key?("expected")
      has_errors = spec.key?("errors")
      unless has_expected || has_errors
        issues << "missing both 'expected' and 'errors' — one is required"
      end

      issues
    end
  end
end

exit SpecSchemaVerifier.run if $PROGRAM_NAME == __FILE__
