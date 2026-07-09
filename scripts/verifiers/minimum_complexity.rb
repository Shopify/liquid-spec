#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifier: feature-based minimum complexity floors
#
# Specs that use advanced features must sit above the beginner ramp.
# The floor depends on the feature — Ruby-specific content and inline
# errors belong above 100; portable drops above 200; template factories
# and Shopify-specific features above 200.
#
# Usage: ruby -Ilib scripts/verifiers/minimum_complexity.rb
# Exit code is non-zero if any violation is found.

require "yaml"

# Feature → minimum complexity floor
FEATURE_FLOORS = {
  "ruby_types"            => 100,
  "ruby_drops"            => 100,
  "binary_data"           => 100,
  "drops"                 => 200,
  "template_factory"      => 200,
  "drop_class_output"     => 100,
  "shopify_tags"          => 200,
  "shopify_objects"       => 200,
  "shopify_filters"       => 200,
  "shopify_error_handling"=> 200,
  "shopify_blank"         => 200,
  "shopify_string_access" => 200,
  "shopify_error_format"  => 200,
  "shopify_includes"      => 200,
}.freeze

# Non-feature conditions that also impose a floor
CONDITION_FLOORS = {
  "instantiate: in environment" => 100,
  "render_errors: true"         => 100,
  "error_mode: strict2"         => 100,
}.freeze

SPEC_ROOT ||= File.expand_path("../../specs", __dir__)

module MinimumComplexityVerifier
  class << self
    def run
      offenders = []

      each_spec do |spec|
        issues = check_spec(spec)
        next if issues.empty?
        offenders << {
          file: spec[:file],
          line: spec[:line],
          name: spec[:name],
          complexity: spec[:complexity],
          issues: issues,
        }
      end

      if offenders.empty?
        puts "OK: all specs meet their feature-based minimum complexity floors."
        return 0
      end

      puts "Found #{offenders.size} spec(s) below their minimum complexity floor:\n\n"
      offenders.each do |o|
        c = o[:complexity] || "unset"
        puts "  #{o[:file]}:#{o[:line]}  #{o[:name]}  (complexity: #{c})"
        o[:issues].each { |i| puts "    - #{i}" }
        puts
      end
      1
    end

    private

    def each_spec
      Dir.glob(File.join(SPEC_ROOT, "**/*.yml")).sort.each do |file|
        rel = file.sub("#{SPEC_ROOT}/", "")
        data = safe_load(file)
        next unless data

        specs = extract_specs(data)
        next unless specs

        suite_min = suite_minimum_complexity(file)
        name_lines = index_name_lines(file)
        specs.each_with_index do |spec, idx|
          next unless spec.is_a?(Hash)
          name = spec["name"] || "(spec ##{idx + 1})"
          line = name_lines[name] || 0
          yield({ file: rel, line: line, name: name,
                  complexity: spec["complexity"] || suite_min,
                  features: spec["features"] || [],
                  environment: spec["environment"],
                  render_errors: spec["render_errors"],
                  error_mode: spec["error_mode"] })
        end
      end
    end

    def check_spec(spec)
      issues = []
      c = spec[:complexity]

      # Check feature-based floors
      (spec[:features] || []).each do |feat|
        feat_str = feat.to_s
        floor = FEATURE_FLOORS[feat_str]
        if floor && (c.nil? || c < floor)
          issues << "feature '#{feat_str}' requires complexity >= #{floor}, got #{c || 'unset'}"
        end
      end

      # Check condition-based floors
      env = spec[:environment]
      if env && has_instantiate?(env)
        floor = CONDITION_FLOORS["instantiate: in environment"]
        if c.nil? || c < floor
          issues << "instantiate: drop in environment requires complexity >= #{floor}, got #{c || 'unset'}"
        end
      end

      if spec[:render_errors] == true
        floor = CONDITION_FLOORS["render_errors: true"]
        if c.nil? || c < floor
          issues << "render_errors: true requires complexity >= #{floor}, got #{c || 'unset'}"
        end
      end

      em = spec[:error_mode]
      if em && em.to_s == "strict2"
        floor = CONDITION_FLOORS["error_mode: strict2"]
        if c.nil? || c < floor
          issues << "error_mode: strict2 requires complexity >= #{floor}, got #{c || 'unset'}"
        end
      end

      issues
    end

    def has_instantiate?(obj, depth = 0)
      return false if depth > 20  # prevent infinite recursion
      case obj
      when Hash
        obj.any? { |k, v| (k.is_a?(String) && k.start_with?("instantiate:")) || has_instantiate?(v, depth + 1) }
      when Array
        obj.any? { |e| has_instantiate?(e, depth + 1) }
      when String
        obj.start_with?("instantiate:")
      else
        false
      end
    end

    def suite_minimum_complexity(spec_file)
      suite_file = File.join(File.dirname(spec_file), "suite.yml")
      return nil unless File.exist?(suite_file)
      suite = safe_load(suite_file)
      return nil unless suite.is_a?(Hash)
      suite["minimum_complexity"]
    end

    def safe_load(file)
      YAML.unsafe_load(File.read(file))
    rescue
      nil
    end

    def extract_specs(data)
      case data
      when Array
        data
      when Hash
        data["specs"]
      end
    end

    def index_name_lines(file)
      names = {}
      File.readlines(file).each_with_index do |line, idx|
        if line =~ /^\s*-?\s*name:\s*(.+)$/
          names[$1.strip] = idx + 1
        end
      end
      names
    end
  end
end

exit MinimumComplexityVerifier.run if $PROGRAM_NAME == __FILE__
