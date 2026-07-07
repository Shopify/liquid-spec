#!/usr/bin/env ruby
# frozen_string_literal: true

# Runner: loads and executes all verifiers in scripts/verifiers/ in-process.
#
# Each verifier is a Ruby file that defines a module with a `run` class method
# returning 0 on success or non-zero on violations, and ends with
# `exit ModuleName.run if $PROGRAM_NAME == __FILE__` so it can also run standalone.
#
# Verifiers marked `# advisory: true` in their header are non-blocking — they
# report findings but don't fail the overall exit code.
#
# Usage: ruby -Ilib scripts/verify.rb
# Exit code is non-zero if any blocking verifier fails.

require "stringio"

VERIFIERS_DIR = File.expand_path("verifiers", __dir__)
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# Map verifier filenames to their module constants.
VERIFIER_MODULES = {
  "lax_mode_declared"   => "LaxModeDeclaredVerifier",
  "lax_placement"       => "LaxPlacementVerifier",
  "minimum_complexity"  => "MinimumComplexityVerifier",
  "ruby_type_tags"      => "RubyTypeTagVerifier",
  "spec_schema"         => "SpecSchemaVerifier",
  "jsonrpc_portability"  => "JsonRpcPortabilityVerifier",
  "cross_mode_compatibility" => "CrossModeCompatibilityVerifier",
  "parse_mode_annotation"    => "ParseModeAnnotationVerifier",
  "spec_name_collisions"     => "SpecNameCollisionVerifier",
  "filesystem_extensions"    => "FilesystemExtensionVerifier",
}

results = []

Dir.glob(File.join(VERIFIERS_DIR, "*.rb")).sort.each do |script|
  name = File.basename(script, ".rb")
  next if name == "verify" # skip self

  # Check if this is an advisory verifier
  header = File.read(script, 200)
  advisory = header.include?("advisory: true")

  # Load the verifier file (the `exit ... if $PROGRAM_NAME` guard prevents exit)
  load(script)

  mod_name = VERIFIER_MODULES[name]
  unless mod_name && Object.const_defined?(mod_name)
    warn "WARNING: could not find module #{mod_name} in #{name}.rb — skipping"
    next
  end

  # Capture stdout during run, then print it
  mod = Object.const_get(mod_name)
  captured = StringIO.new
  original_stdout = $stdout
  $stdout = captured
  exit_code = mod.run
  $stdout = original_stdout

  output = captured.string
  # Strip progress noise (e.g. "Testing spec N/M..." with carriage-return overwrites)
  output = output.gsub(/\r/, "\n").lines.reject { |l| l.strip =~ /\ATesting spec \d+\/\d+/ }.join
  # Print the verifier's output
  puts output unless output.empty?

  results << { name: name, exit_code: exit_code || 0, advisory: advisory }
end

puts "=" * 60
puts "Check summary:"
puts "=" * 60
failures = 0
results.each do |r|
  status = if r[:exit_code] == 0
    "PASS"
  elsif r[:advisory]
    "ADVISORY"
  else
    "FAIL"
  end
  puts "  #{status}  #{r[:name]}"
  failures += 1 if r[:exit_code] != 0 && !r[:advisory]
end

if failures.zero?
  advisory_count = results.count { |r| r[:advisory] && r[:exit_code] != 0 }
  suffix = advisory_count > 0 ? " (#{advisory_count} advisory check(s) have findings — see output above)" : ""
  puts "\nAll #{results.size} checks passed#{suffix}."
  exit 0
else
  puts "\n#{failures} of #{results.size} checks failed."
  exit 1
end
