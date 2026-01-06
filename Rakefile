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
  system("ruby", "bin/liquid-spec", "examples/liquid_ruby.rb", "--no-max-failures") || abort
end

# Spec generation tasks (only needed for development)
import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

desc "Generate spec tests from Shopify/liquid"
task generate: ["generate:liquid_ruby", "generate:standard_filters"]
