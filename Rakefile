require 'rake'
require 'rake/testtask'
require "bundler/gem_tasks"

import("tasks/dawn.rake")
import("tasks/liquid_ruby.rake")
import("tasks/standard_filters.rake")

task :default => :test

Rake::TestTask.new do |t|
  t.libs << FileList['lib', 'tests']
  t.pattern = 'tests/**/*_test.rb'
  t.verbose = false
end
