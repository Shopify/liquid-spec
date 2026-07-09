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
# - error_mode (if present) is one of strict/strict2/lax (single or array)
# - environment/filesystem (if present) are hashes
# - Must have either expected or errors (but not both)
# - render_errors (if present) is a boolean
# - errors sub-keys are from {parse_error, render_error, output}
# - generate (if present) has valid field definitions
# - Unknown fields are flagged
# - _metadata (if present) has valid keys
#
# Usage: ruby -Ilib scripts/verifiers/spec_schema.rb
# Exit code is non-zero if any violation is found.

require "yaml"

# ── Valid values ──────────────────────────────────────────────────────────────

# Union of FEATURES (adapter_dsl.rb), FEATURE_DOCS (features.rb), and
# auto-generated parsing tags from lazy_spec.rb.
VALID_FEATURES = %w[
  core
  inline_errors
  ruby_types
  lax_parsing
  strict_parsing
  strict2_parsing
  self_environment_shadowing
  shopify_tags
  shopify_objects
  shopify_filters
  shopify_error_handling
  shopify_blank
  shopify_string_access
  shopify_error_format
  shopify_includes
  ruby_drops
  drop_class_output
  template_factory
  binary_data
  strict2_blank_body_errors
  drops
  randomness
  shopify_resource_limits
  activesupport
].freeze

VALID_ERROR_MODES = %w[strict strict2 lax warn].freeze

VALID_ERROR_KEYS = %w[parse_error render_error output line position].freeze
# Keys whose values are arrays of patterns (line/position are integers)
ARRAY_ERROR_KEYS = %w[parse_error render_error output].freeze

VALID_GENERATE_TYPES = %w[numeric string boolean].freeze

# Spec-level fields and their expected types.
# nil type = any type acceptable (just presence check).
SPEC_FIELDS = {
  "name"              => String,
  "template"          => String,
  "expected"          => String,
  "expected_pattern"  => String,
  "errors"            => Hash,
  "complexity"        => Integer,
  "features"          => Array,
  "error_mode"        => nil,  # String or Array
  "environment"       => Hash,
  "filesystem"        => Hash,
  "hint"              => String,
  "render_errors"     => nil,  # Boolean
  "url"               => String,
  "generate"          => Hash,
  "resource_limits"   => Hash,
  "caller_location"   => String,
  "message"           => String,
  "template_name"     => String,
  "issue"             => String,
  "exception_renderer"=> Hash,
  "template_factory"  => Hash,
  "context_klass"     => String,
}.freeze

REQUIRED_SPEC_FIELDS = %w[name template].freeze

# Metadata-level fields and their expected types.
METADATA_FIELDS = {
  "hint"              => String,
  "doc"               => String,
  "features"          => Array,
  "minimum_complexity"=> Integer,
  "required_options"  => Hash,
  "complexity"        => Integer,
  "data_files"        => Array,
}.freeze

SPEC_ROOT ||= File.expand_path("../../specs", __dir__)

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

        # Check _metadata if present
        if data.is_a?(Hash) && data["_metadata"]
          meta_issues = check_metadata(data["_metadata"])
          unless meta_issues.empty?
            offenders << { file: rel, line: 0, name: "(_metadata)", issues: meta_issues }
          end
        end

        specs = extract_specs(data)
        next unless specs.is_a?(Array)  # skip non-spec files (data files, etc.)

        suite_min_complexity = suite_minimum_complexity(file)
        specs.each_with_index do |spec, idx|
          next unless spec.is_a?(Hash)
          issues = check_spec(spec, suite_min_complexity: suite_min_complexity)
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
      Dir.glob(File.join(SPEC_ROOT, "**/*.yml")).sort.reject { |f| File.basename(f) == "suite.yml" }
    end

    def relative_path(path)
      path.sub("#{SPEC_ROOT}/", "")
    end

    def suite_minimum_complexity(spec_file)
      suite_dir = File.dirname(spec_file)
      suite_file = File.join(suite_dir, "suite.yml")
      return nil unless File.exist?(suite_file)
      suite = YAML.unsafe_load(File.read(suite_file)) rescue nil
      return nil unless suite.is_a?(Hash)
      suite["minimum_complexity"]
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

    def check_metadata(meta)
      issues = []
      unless meta.is_a?(Hash)
        issues << "_metadata must be a hash"
        return issues
      end

      # Check for unknown metadata keys
      meta.each_key do |key|
        unless METADATA_FIELDS.key?(key)
          issues << "unknown _metadata field '#{key}' (valid: #{METADATA_FIELDS.keys.join(", ")})"
        end
      end

      # Type-check known metadata fields
      METADATA_FIELDS.each do |field, type|
        next unless meta.key?(field)
        val = meta[field]
        next if type.nil?
        if type == Integer && val.is_a?(Integer)
          # OK
        elsif type == Array && val.is_a?(Array)
          # OK
        elsif type == Hash && val.is_a?(Hash)
          # OK
        elsif !type.is_a?(Class) || !val.is_a?(type)
          issues << "_metadata '#{field}' must be a #{type}, got #{val.class}"
        end
      end

      # Validate metadata features
      if meta["features"].is_a?(Array)
        meta["features"].each do |feat|
          unless VALID_FEATURES.include?(feat.to_s)
            issues << "_metadata has unknown feature tag '#{feat}' (valid: #{VALID_FEATURES.join(", ")})"
          end
        end
      end

      # Validate metadata minimum_complexity range
      mc = meta["minimum_complexity"]
      if mc.is_a?(Integer) && (mc < 1 || mc > 1000)
        issues << "_metadata minimum_complexity #{mc} is not in 1..1000"
      end

      # Validate metadata complexity range
      mc = meta["complexity"]
      if mc.is_a?(Integer) && (mc < 0 || mc > 1000)
        issues << "_metadata complexity #{mc} is not in 1..1000"
      end

      issues
    end

      def check_spec(spec, suite_min_complexity: nil)
        issues = []

        # Required fields
        REQUIRED_SPEC_FIELDS.each do |field|
          val = spec[field]
          case field
          when "name"
            unless val.is_a?(String) && !val.empty?
              issues << "missing or empty 'name'"
            end
          when "template"
            unless val.is_a?(String)
              issues << "missing 'template' (must be a string)"
            end
          end
        end

        # Unknown fields
        spec.each_key do |key|
          unless SPEC_FIELDS.key?(key)
            issues << "unknown field '#{key}' (valid: #{SPEC_FIELDS.keys.join(", ")})"
          end
        end

        # Type-check known fields
        SPEC_FIELDS.each do |field, type|
          next unless spec.key?(field)
          next if type.nil?
          val = spec[field]
          next if val.nil?  # nil is valid for optional fields
          if type == Integer
            unless val.is_a?(Integer)
              issues << "'#{field}' must be an integer, got #{val.class}"
            end
          elsif type == Array
            unless val.is_a?(Array)
              issues << "'#{field}' must be an array, got #{val.class}"
            end
          elsif type == Hash
            unless val.is_a?(Hash)
              issues << "'#{field}' must be a hash, got #{val.class}"
            end
          elsif type.is_a?(Class) && !val.is_a?(type)
            issues << "'#{field}' must be a #{type}, got #{val.class}"
          end
        end

        # complexity: required, integer 0..1000.
        # If the spec doesn't set it but the suite has minimum_complexity,
        # the spec inherits the suite default — that's intentional, not a violation.
        c = spec["complexity"]
        if !c && c != 0  # complexity 0 is falsy but valid
          if suite_min_complexity
            # OK — inherits suite minimum_complexity
          else
            issues << "missing 'complexity' — every spec must have a complexity score (0..1000)"
          end
        elsif !c.is_a?(Integer)
          issues << "complexity must be an integer, got #{c.class}"
        elsif c < 0 || c > 1000
          issues << "complexity #{c} is not in 0..1000"
        end



      # features: array of known feature names, no duplicates
      f = spec["features"]
      if f.is_a?(Array)
        f.each do |feat|
          feat_str = feat.to_s
          unless VALID_FEATURES.include?(feat_str)
            issues << "unknown feature tag '#{feat_str}' (valid: #{VALID_FEATURES.join(", ")})"
          end
        end
        if f.map(&:to_s).uniq.size != f.size
          issues << "features has duplicate entries"
        end
      end

      # error_mode: one or more of strict/strict2/lax, no duplicates
      em = spec["error_mode"]
      if em
        modes = em.is_a?(Array) ? em : [em]
        modes.each do |m|
          unless VALID_ERROR_MODES.include?(m.to_s)
            issues << "error_mode '#{m}' is not one of #{VALID_ERROR_MODES.join(", ")}"
          end
        end
        if modes.map(&:to_s).uniq.size != modes.size
          issues << "error_mode has duplicate entries"
        end
      end

      # errors: hash with valid sub-keys
      errors = spec["errors"]
      if errors.is_a?(Hash)
        errors.each_key do |key|
          unless VALID_ERROR_KEYS.include?(key.to_s)
            issues << "errors has unknown key '#{key}' (valid: #{VALID_ERROR_KEYS.join(", ")})"
          end
        end
        # parse_error/render_error/output must be arrays of patterns
        # line/position must be integers
        errors.each do |key, val|
          next unless VALID_ERROR_KEYS.include?(key.to_s)
          if ARRAY_ERROR_KEYS.include?(key.to_s)
            unless val.is_a?(Array)
              issues << "errors.#{key} must be an array of patterns, got #{val.class}"
            end
          elsif key.to_s == "line" || key.to_s == "position"
            unless val.is_a?(Integer)
              issues << "errors.#{key} must be an integer, got #{val.class}"
            end
          end
        end
      end

      # Must have either expected or errors (but not both)
      has_expected = spec.key?("expected") || spec.key?("expected_pattern")
      has_errors = spec.key?("errors")
      unless has_expected || has_errors
        issues << "missing both 'expected'/'expected_pattern' and 'errors' — one is required"
      end
      if has_expected && has_errors
        issues << "spec has both 'expected' and 'errors' — only one is allowed"
      end

      # render_errors: must be boolean
      re = spec["render_errors"]
      if re != nil && ![true, false].include?(re)
        issues << "render_errors must be a boolean, got #{re.class}"
      end

      # generate: hash with valid field definitions
      gen = spec["generate"]
      if gen.is_a?(Hash)
        gen.each do |field_name, field_def|
          unless field_def.is_a?(Hash)
            issues << "generate.#{field_name} must be a hash with type/min/max, got #{field_def.class}"
            next
          end
          unless field_def["type"]
            issues << "generate.#{field_name} missing 'type' (valid: #{VALID_GENERATE_TYPES.join(", ")})"
          else
            unless VALID_GENERATE_TYPES.include?(field_def["type"].to_s)
              issues << "generate.#{field_name} has unknown type '#{field_def["type"]}' (valid: #{VALID_GENERATE_TYPES.join(", ")})"
            end
          end
          if field_def["min"] && !field_def["min"].is_a?(Integer)
            issues << "generate.#{field_name} min must be an integer, got #{field_def["min"].class}"
          end
          if field_def["max"] && !field_def["max"].is_a?(Integer)
            issues << "generate.#{field_name} max must be an integer, got #{field_def["max"].class}"
          end
          if field_def["min"].is_a?(Integer) && field_def["max"].is_a?(Integer) && field_def["min"] > field_def["max"]
            issues << "generate.#{field_name} min (#{field_def["min"]}) > max (#{field_def["max"]})"
          end
        end
      end

      issues
    end
  end
end

exit SpecSchemaVerifier.run if $PROGRAM_NAME == __FILE__
