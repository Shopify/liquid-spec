# frozen_string_literal: true

require "rake"
require "rake/testtask"
require_relative("tasks/helpers")

import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

task default: :test

# Standard interpreted test
Rake::TestTask.new(:test) do |t|
  t.libs << FileList["lib", "test"]
  t.pattern = "test/liquid_ruby_test.rb"
  t.verbose = false
end

# Compiled template test (requires RUBY_BOX=1)
Rake::TestTask.new(:test_compiled) do |t|
  t.libs << FileList["lib", "test"]
  t.pattern = "test/liquid_ruby_compiled_test.rb"
  t.verbose = false
  t.description = "Run specs with compiled templates (requires RUBY_BOX=1)"
end

desc "Run all spec tests (interpreted and compiled)"
task :test_all => [:test, :test_compiled]

desc "Generate spec tests from Shopify/liquid"
task generate: ["generate:liquid_ruby", "generate:standard_filters"]
