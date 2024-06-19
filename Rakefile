require 'rake'
require 'rake/testtask'
require "bundler/gem_tasks"

task default: :test

Rake::TestTask.new do |t|
  t.libs << FileList['lib', 'tests']
  t.pattern = 'tests/**/*_test.rb'
  t.verbose = false
end
