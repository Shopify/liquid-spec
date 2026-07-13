#!/usr/bin/env ruby
# frozen_string_literal: true

# Lint: a spec restricted to strict or strict2 must actually need that
# restriction. If liquid-ruby produces the same status and output in both
# modes, declare error_mode: [strict2, strict] so adapters supporting either
# strictness exercise it.

require "liquid/spec/spec_loader"
require "liquid/spec/adapter_runner"
require "liquid/spec/time_freezer"

module StrictModeCompatibilityVerifier
  class << self
    def run
      adapter = Liquid::Spec::AdapterRunner.new(name: "strict-mode-verifier")
        .load_dsl(reference_adapter)
      adapter.ensure_setup!

      offenders = []
      Liquid::Spec::TimeFreezer.freeze_spec_time do
        Liquid::Spec::SpecLoader.load_all.each do |spec|
          next unless spec.error_modes.length == 1
          next unless [:strict, :strict2].include?(spec.error_mode)

          strict2 = result_for(adapter, spec, :strict2)
          strict = result_for(adapter, spec, :strict)
          next unless strict2 == strict

          offenders << spec
        end
      end

      if offenders.empty?
        puts "OK: all strict/strict2-only specs require their single-mode declaration."
        return 0
      end

      puts "Found #{offenders.size} strict/strict2 spec(s) compatible with both modes:\n\n"
      offenders.each do |spec|
        puts "  #{relative_path(spec.source_file)}:#{spec.line_number}  #{spec.name}"
      end
      puts "\nDeclare error_mode: [strict2, strict] for each compatible spec."
      1
    end

    private

    def result_for(adapter, spec, mode)
      result = adapter.run_single(spec.with_error_mode(mode))
      [result.status, result.output.to_s]
    end

    def reference_adapter
      File.expand_path("../../examples/liquid_ruby.rb", __dir__)
    end

    def relative_path(path)
      path.sub(%r{\A#{Regexp.escape(Dir.pwd)}/}, "")
    end
  end
end

exit StrictModeCompatibilityVerifier.run if $PROGRAM_NAME == __FILE__
