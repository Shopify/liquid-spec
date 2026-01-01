# frozen_string_literal: true

require "rake"
require_relative("tasks/helpers")

import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

task default: :test

desc "Run liquid-spec tests using the CLI runner"
task :test do
  require_relative "lib/liquid/spec/cli"
  Liquid::Spec::CLI.run(["run", "examples/liquid_ruby.rb"])
end

desc "Generate spec tests from Shopify/liquid"
task generate: ["generate:liquid_ruby", "generate:standard_filters"]
