# frozen_string_literal: true

require "rake"
require "rake/testtask"
require "bundler/gem_tasks"

import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

task default: :test

Rake::TestTask.new do |t|
  t.libs << FileList["lib", "test"]
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end
