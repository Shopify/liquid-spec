# frozen_string_literal: true

require "rake"
require "rake/testtask"
require "fileutils"

require_relative "lib/liquid/spec/version"

task default: :test

BUILD_DIR = "build"

# Unit tests for liquid-spec itself
Rake::TestTask.new(:unit_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
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

desc "Run all tests (unit tests + integration tests)"
task test: [:unit_test, :integration_test]

desc "Run integration tests using the CLI runner"
task :integration_test do
  ruby("bin/liquid-spec", "examples/liquid_ruby.rb") || abort
end

desc "Run liquid-spec tests against all available example adapters"
task :test_all_adapters, [:compare] do |_t, args|
  compare_mode = args[:compare] == "compare" || ENV["COMPARE"] == "1"
  adapters = Dir["examples/*.rb"]
  available = []
  skipped = []

  adapters.each do |adapter|
    adapter_name = File.basename(adapter, ".rb")

    # Check if the adapter's dependencies are available
    case adapter_name
    when "liquid_c"
      begin
        require "liquid/c"
        available << adapter if defined?(Liquid::C)
      rescue LoadError
        skipped << [adapter, "liquid-c gem not installed"]
      end
    when "liquid_ruby", "liquid_ruby_strict"
      begin
        require "liquid"
        available << adapter
      rescue LoadError
        skipped << [adapter, "liquid gem not installed"]
      end
    else
      # Unknown adapter - try to load and see
      available << adapter
    end
  end

  puts "Testing #{available.size} adapter(s)..."
  puts ""

  skipped.each do |adapter, reason|
    puts "SKIP: #{File.basename(adapter)} (#{reason})"
  end
  puts "" if skipped.any?

  failed = []
  available.each do |adapter|
    puts "=" * 60
    puts "Testing: #{File.basename(adapter)}"
    puts "=" * 60
    puts ""

    cmd = ["ruby", "bin/liquid-spec", adapter]
    cmd << "--compare" if compare_mode
    success = system(*cmd)
    failed << adapter unless success

    puts ""
  end

  puts "=" * 60
  puts "Summary"
  puts "=" * 60
  puts "Passed: #{available.size - failed.size}/#{available.size}"
  puts "Skipped: #{skipped.size}" if skipped.any?

  if failed.any?
    puts ""
    puts "Failed adapters:"
    failed.each { |a| puts "  - #{File.basename(a)}" }
    abort
  end
end

# Spec generation tasks (only needed for development)
import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

desc "Generate spec tests from Shopify/liquid"
task generate: ["generate:liquid_ruby", "generate:standard_filters"]
