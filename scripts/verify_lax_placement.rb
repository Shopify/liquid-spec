#!/usr/bin/env ruby
# frozen_string_literal: true

# This script verifies that specs are correctly placed:
# - Specs that only work in lax mode MUST be in the liquid_ruby_lax suite
# - Specs that work in strict mode (or both) can be anywhere
# - Specs that explicitly test strict mode rejection (error_mode: :strict with render_errors: true)
#   are skipped as they intentionally test error behavior
#
# Usage: ruby -I../liquid/lib -Ilib scripts/verify_lax_placement.rb

require "liquid"
require "liquid/spec"
require "liquid/spec/suite"
require "liquid/spec/deps/liquid_ruby"
require "liquid/spec/yaml_initializer"
require "timecop"

module LaxPlacementVerifier
  TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze

  class << self
    def run
      Timecop.freeze(TEST_TIME) do
        verify_all_specs
      end
    end

    private

    def verify_all_specs
      # Load all specs from liquid_ruby and liquid_ruby_lax suites
      liquid_ruby_suite = Liquid::Spec::Suite.find(:liquid_ruby)
      liquid_ruby_lax_suite = Liquid::Spec::Suite.find(:liquid_ruby_lax)

      unless liquid_ruby_suite && liquid_ruby_lax_suite
        puts "Error: Could not find required suites"
        exit 1
      end

      # Get specs from each suite
      strict_suite_specs = liquid_ruby_suite.specs
      lax_suite_specs = liquid_ruby_lax_suite.specs

      # Track spec names in lax suite for quick lookup
      lax_suite_names = lax_suite_specs.map(&:name).to_set

      # Results tracking
      results = {
        strict_only: [],        # Works in strict, may or may not work in lax
        lax_only: [],           # Only works in lax
        both: [],               # Works in both modes
        neither: [],            # Works in neither (broken spec)
        strict_rejection: [],   # Tests that strict mode rejects invalid syntax
      }

      misplaced = []  # Lax-only specs not in lax suite

      puts "Verifying #{strict_suite_specs.size} specs from liquid_ruby suite..."
      puts "Verifying #{lax_suite_specs.size} specs from liquid_ruby_lax suite..."
      puts ""

      all_specs = strict_suite_specs + lax_suite_specs
      total = all_specs.size

      all_specs.each_with_index do |spec, idx|
        print "\r  Testing spec #{idx + 1}/#{total}..."
        $stdout.flush

        # Skip specs that explicitly test strict mode rejection behavior
        # These have error_mode: :strict and render_errors: true, meaning they
        # expect a syntax error to be rendered as output
        if spec.error_mode&.to_sym == :strict && spec.render_errors
          results[:strict_rejection] << spec
          next
        end

        strict_result = test_spec_with_mode(spec, :strict)
        lax_result = test_spec_with_mode(spec, :lax)

        in_lax_suite = lax_suite_names.include?(spec.name)

        if strict_result == :pass && lax_result == :pass
          results[:both] << spec
        elsif strict_result == :pass
          results[:strict_only] << spec
        elsif lax_result == :pass
          results[:lax_only] << spec
          # This is a lax-only spec - it must be in the lax suite
          unless in_lax_suite
            misplaced << {
              spec: spec,
              strict_error: strict_result,
            }
          end
        else
          results[:neither] << {
            spec: spec,
            strict_error: strict_result,
            lax_error: lax_result,
          }
        end
      end

      puts "\r  Testing spec #{total}/#{total}... done!"
      puts ""

      # Print summary
      puts "=" * 60
      puts "RESULTS"
      puts "=" * 60
      puts ""
      puts "Works in strict mode only: #{results[:strict_only].size}"
      puts "Works in lax mode only:    #{results[:lax_only].size}"
      puts "Works in both modes:       #{results[:both].size}"
      puts "Works in neither mode:     #{results[:neither].size}"
      puts "Strict rejection tests:    #{results[:strict_rejection].size} (skipped)"
      puts ""

      # Report misplaced specs
      if misplaced.any?
        puts "=" * 60
        puts "MISPLACED SPECS (lax-only but not in lax suite)"
        puts "=" * 60
        puts ""
        misplaced.each do |m|
          puts "  #{m[:spec].name}"
          puts "    Template: #{m[:spec].template.inspect[0..60]}..."
          puts "    Strict error: #{format_error(m[:strict_error])}"
          puts ""
        end
        puts "Total misplaced: #{misplaced.size}"
        puts ""
      end

      # Report broken specs
      if results[:neither].any?
        puts "=" * 60
        puts "BROKEN SPECS (fail in both modes)"
        puts "=" * 60
        puts ""
        results[:neither].each do |n|
          puts "  #{n[:spec].name}"
          puts "    Template: #{n[:spec].template.inspect[0..60]}..."
          puts "    Strict error: #{format_error(n[:strict_error])}"
          puts "    Lax error: #{format_error(n[:lax_error])}"
          puts ""
        end
      end

      # Exit with error if there are misplaced specs
      if misplaced.any?
        puts "FAILED: #{misplaced.size} specs are lax-only but not in the lax suite"
        exit 1
      else
        puts "OK: All lax-only specs are correctly placed in the lax suite"
        exit 0
      end
    end

    def test_spec_with_mode(spec, mode)
      compile_options = {
        line_numbers: true,
        error_mode: mode,
      }

      begin
        template = Liquid::Template.parse(spec.template, **compile_options)
      rescue Liquid::SyntaxError => e
        return { type: :syntax_error, message: e.message }
      end

      # Set template name if specified
      if spec.template_name && template.respond_to?(:name=)
        template.name = spec.template_name
      end

      # Build assigns
      assigns = deep_copy(spec.environment || {})

      # Build render context
      render_options = {
        registers: build_registers(spec),
        strict_variables: false,
        strict_filters: false,
      }

      begin
        actual = template.render(assigns, **render_options)
        if actual == spec.expected
          :pass
        else
          { type: :mismatch, expected: spec.expected, actual: actual }
        end
      rescue StandardError => e
        { type: :render_error, message: "#{e.class}: #{e.message}" }
      end
    end

    def build_registers(spec)
      registers = {}
      registers[:file_system] = build_file_system(spec)
      registers[:template_factory] = spec.template_factory if spec.template_factory
      registers
    end

    def build_file_system(spec)
      case spec.filesystem
      when Hash
        StubFileSystem.new(spec.filesystem)
      when nil
        Liquid::BlankFileSystem.new
      else
        spec.filesystem
      end
    end

    def deep_copy(obj, seen = {}.compare_by_identity)
      return seen[obj] if seen.key?(obj)

      case obj
      when Hash
        copy = obj.class.new
        seen[obj] = copy
        obj.each { |k, v| copy[deep_copy(k, seen)] = deep_copy(v, seen) }
        copy
      when Array
        copy = []
        seen[obj] = copy
        obj.each { |v| copy << deep_copy(v, seen) }
        copy
      else
        obj
      end
    end

    def format_error(error)
      case error
      when :pass
        "PASS"
      when Hash
        case error[:type]
        when :syntax_error
          "SyntaxError: #{error[:message][0..50]}"
        when :mismatch
          "Output mismatch"
        when :render_error
          error[:message][0..50]
        else
          error.inspect[0..50]
        end
      else
        error.inspect[0..50]
      end
    end
  end
end

LaxPlacementVerifier.run
