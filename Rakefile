# frozen_string_literal: true

require "rake"
require "fileutils"
require_relative "lib/liquid/spec/version"
require_relative("tasks/helpers")

import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

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
  require_relative "lib/liquid/spec/cli"
  Liquid::Spec::CLI.run(["run", "examples/liquid_ruby.rb"])
end

desc "Generate spec tests from Shopify/liquid"
task generate: ["generate:liquid_ruby", "generate:standard_filters"]
