# frozen_string_literal: true

require "rake"
require "rake/testtask"
require "bundler/gem_tasks"
require_relative("tasks/helpers")

import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

task default: :test

Rake::TestTask.new do |t|
  t.libs << FileList["lib", "test"]
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

desc "Generate spec tests from Shopify/liquid"
task generate: ["generate:liquid_ruby", "generate:standard_filters"]
