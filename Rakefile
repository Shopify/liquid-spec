# frozen_string_literal: true

require "rake"
require "rake/testtask"
require "fileutils"

require_relative "lib/liquid/spec/version"

task default: :prepush

BUILD_DIR = "build"

# Unit tests for liquid-spec itself
Rake::TestTask.new(:unit_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/json_rpc_integration_test.rb")
  t.warning = false
end

desc "Build the gem into the #{BUILD_DIR} directory"
task :build do
  FileUtils.mkdir_p(BUILD_DIR)
  gemspec = Dir["*.gemspec"].first
  system("gem", "build", gemspec, "--output", File.join(BUILD_DIR, "liquid-spec-#{Liquid::Spec::VERSION}.gem")) || abort
end

desc "Build and install the gem locally"
task install: :build do
  system("gem", "install", File.join(BUILD_DIR, "liquid-spec-#{Liquid::Spec::VERSION}.gem")) || abort
end

desc "Run unit tests for liquid-spec itself"
task :test do
  puts ""
  puts "!!! WARNING: rake test just runs the unit tests of liquid-spec,"
  puts "!!!          run liquid-spec itself via the CLI interface"
  puts ""
  Rake::Task[:unit_test].invoke
end

desc "Run liquid-spec against the reference liquid-ruby adapter"
task :run do
  system("bundle", "exec", "ruby", "bin/liquid-spec", "run", "examples/liquid_ruby.rb", "--no-max-failures") || abort
end

desc "Run liquid-spec matrix across all adapters"
task :matrix do
  system("bundle", "exec", "ruby", "bin/liquid-spec", "matrix", "--all") || abort
end

desc "Verify every spec feature tag is covered by at least one reference adapter"
task :coverage_check do
  require "yaml"
  require "set"

  base = File.expand_path(__dir__)

  # Collect all feature tags used across spec YAML files
  spec_tags = Set.new
  Dir.glob(File.join(base, "specs/**/*.yml")).each do |f|
    begin
      data = YAML.safe_load(File.read(f), permitted_classes: [Symbol, Range], aliases: true)
      next unless data

      meta = data.is_a?(Hash) ? (data["_metadata"] || {}) : {}
      (meta["features"] || []).each { |t| spec_tags << t.to_sym }

      specs = data.is_a?(Hash) ? (data["specs"] || []) : (data.is_a?(Array) ? data : [])
      specs.each do |spec|
        (spec["features"] || []).each { |t| spec_tags << t.to_sym } if spec.is_a?(Hash)
      end
    rescue
    end
  end

  # Extract missing_features from each reference adapter via static analysis.
  # We parse the config.missing_features = [...] line rather than loading the
  # adapter (which would require all adapter dependencies to be installed).
  adapter_files = Dir.glob(File.join(base, "examples/*.rb"))
  adapter_missing = {}
  adapter_files.each do |path|
    source = File.read(path)
    if (m = source.match(/config\.missing_features\s*=\s*\[(.*?)\]/m))
      symbols = m[1].scan(/:(\w+)/).flatten.map(&:to_sym)
      adapter_missing[File.basename(path)] = symbols.to_set
    end
  end

  if adapter_missing.empty?
    abort "Coverage check FAILED — no reference adapters found in examples/"
  end

  # Check: every tag must be NOT-missing in at least one adapter
  orphans = spec_tags.reject do |tag|
    adapter_missing.any? { |_, missing| !missing.include?(tag) }
  end

  if orphans.any?
    abort "Coverage check FAILED — no reference adapter covers these tags:\n  #{orphans.sort.join(', ')}\n\nAdd an example adapter that does not include these in missing_features."
  else
    puts "Coverage check passed: all #{spec_tags.size} feature tags covered across #{adapter_missing.size} reference adapters."
  end
end

desc "Run all spec verifiers (prints findings, does not modify files)"
task :check do
  require_relative "lib/liquid/spec/verifiers"
  status = Liquid::Spec::Verifiers.run
  abort "Verifier gate failed" unless status.zero?
end

desc "Run unit tests then all verifiers (standard pre-push gate)"
task prepush: [:test, :check] do
  puts "\n✓ All pre-push checks passed (test + check)"
end

# Spec generation tasks (only needed for development)
import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

desc "Generate spec tests from Shopify/liquid"
task generate: ["generate:liquid_ruby", "generate:standard_filters"]
