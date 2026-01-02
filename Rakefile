# frozen_string_literal: true

require "rake"
require "fileutils"

require_relative "lib/liquid/spec/version"

task default: :test

BUILD_DIR = "build"

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

desc "Run liquid-spec tests using the CLI runner"
task :test do
  ruby("bin/liquid-spec", "examples/liquid_ruby.rb") || abort
end

# Spec generation tasks (only needed for development)
import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

desc "Generate spec tests from Shopify/liquid"
task generate: ["generate:liquid_ruby", "generate:standard_filters"]
