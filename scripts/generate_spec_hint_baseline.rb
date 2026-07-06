#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerate test/spec_hint_baseline.txt: the frozen list of specs at
# complexity <= 220 that have no spec-level hint (spec.hint). These are existing
# generated/bulk specs grandfathered out of the spec-level-hint gate. Any NEW
# spec at c<=220 without a spec-level hint is caught by the gate (not in this
# baseline). Re-run after intentionally adding spec-level hints to baseline
# entries (it shrinks the baseline).
#
# Usage: ruby -Ilib scripts/generate_spec_hint_baseline.rb

require "liquid"
require "liquid/spec"
require "liquid/spec/suite"
require "liquid/spec/spec_loader"
require "liquid/spec/deps/liquid_ruby"

root = File.expand_path("..", __dir__)
baseline_path = File.join(root, "test", "spec_hint_baseline.txt")

entries = []
Liquid::Spec::Suite.all.each do |suite|
  Liquid::Spec::SpecLoader.load_suite(suite).each do |spec|
    c = spec.complexity || suite.minimum_complexity || 1000
    next unless c <= 220
    next unless spec.hint.to_s.strip.empty?
    rel = spec.source_file.to_s.sub(root + "/", "")
    entries << "#{rel}\t#{spec.name}"
  end
end
entries.sort!
File.write(baseline_path, entries.join("\n") + "\n")
puts "wrote #{entries.size} entries to #{baseline_path}"
