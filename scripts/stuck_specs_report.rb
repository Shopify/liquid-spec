#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "optparse"
require "time"
require "yaml"

options = {
  log: ENV.fetch("LIQUID_SPEC_RESULTS", "/tmp/liquid-spec-results.jsonl"),
  top: 50,
  min_bad: 1,
  max_complexity: nil,
  recent_runs: nil,
  root: File.expand_path("..", __dir__),
}

OptionParser.new do |opts|
  opts.banner = "Usage: scripts/stuck_specs_report.rb [options]"
  opts.on("--log PATH", "Results JSONL path (default: /tmp/liquid-spec-results.jsonl)") { |v| options[:log] = v }
  opts.on("--top N", Integer, "Number of stuck specs to print (default: 50)") { |v| options[:top] = v }
  opts.on("--min-bad N", Integer, "Only include specs with at least N non-success results") { |v| options[:min_bad] = v }
  opts.on("--max-complexity N", Integer, "Only include specs at or below this complexity") { |v| options[:max_complexity] = v }
  opts.on("--recent-runs N", Integer, "Only analyze the last N distinct run IDs in the log") { |v| options[:recent_runs] = v }
  opts.on("--root PATH", "Repository root for resolving spec YAML (default: parent of scripts/)") { |v| options[:root] = File.expand_path(v) }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end.parse!

log_path = File.expand_path(options[:log])
unless File.file?(log_path)
  warn "No results log found at #{log_path}"
  warn "Pass --log PATH or set LIQUID_SPEC_RESULTS=/path/to/liquid-spec-results.jsonl"
  exit 1
end

root = options[:root]

SpecInfo = Struct.new(
  :file, :logical_source, :name, :complexity, :template, :expected, :errors, :environment, :hint,
  keyword_init: true
)

Stats = Struct.new(
  :logical_source, :name, :complexity, :total, :success, :fail, :error, :bad_runs, :versions,
  keyword_init: true
) do
  def bad
    fail + error
  end

  def fail_rate
    total.zero? ? 0.0 : bad.to_f / total
  end
end

def logical_source(path)
  path = path.to_s
  normalized = path.tr("\\", "/")
  if (idx = normalized.rindex("/specs/"))
    normalized[(idx + 1)..]
  elsif normalized.start_with?("specs/")
    normalized
  else
    normalized
  end
end

def safe_load_yaml(path)
  YAML.load_file(
    path,
    permitted_classes: [Regexp, Symbol, Date, Time],
    aliases: true,
  )
rescue Psych::Exception => e
  warn "Skipping unreadable YAML #{path}: #{e.message}"
  nil
end

def each_spec_file(root)
  Dir.glob(File.join(root, "specs", "**", "*.yml")).sort.each do |path|
    next if File.basename(path) == "suite.yml"
    yield path
  end
end

def effective_complexity(spec, metadata)
  (spec["complexity"] || metadata["complexity"] || metadata["minimum_complexity"] || 1000).to_i
end

def effective_hint(spec, metadata)
  spec["hint"] || metadata["hint"]
end

def snippet(value, max = 180)
  return nil if value.nil?

  text = case value
  when String
    value
  else
    value.inspect
  end
  text = text.gsub("\n", "\\n")
  text.length > max ? "#{text[0, max - 1]}…" : text
end

def load_spec_index(root)
  index = {}
  fallback = Hash.new { |h, k| h[k] = [] }

  each_spec_file(root) do |path|
    data = safe_load_yaml(path)
    next unless data

    metadata = data.is_a?(Hash) ? (data["_metadata"] || {}) : {}
    specs = data.is_a?(Array) ? data : data["specs"]
    next unless specs.respond_to?(:each)

    logical = logical_source(path)
    specs.each do |spec|
      next unless spec.is_a?(Hash) && spec["name"]

      info = SpecInfo.new(
        file: path,
        logical_source: logical,
        name: spec["name"],
        complexity: effective_complexity(spec, metadata),
        template: spec["template"],
        expected: spec["expected"],
        errors: spec["errors"],
        environment: spec["environment"],
        hint: effective_hint(spec, metadata),
      )
      index[[logical, info.name]] = info
      fallback[[File.basename(logical), info.name]] << info
    end
  end

  [index, fallback]
end

def last_run_ids(path, count)
  return nil unless count

  ids = []
  last = nil
  File.foreach(path, encoding: Encoding::UTF_8) do |line|
    row = JSON.parse(line) rescue next
    run_id = row[0]
    next if run_id == last

    ids << run_id
    ids.shift while ids.length > count
    last = run_id
  end
  ids.to_h { |id| [id, true] }
end

def find_spec_info(spec_index, basename_fallback, logical_source, name)
  info = spec_index[[logical_source, name]]
  return info if info

  matches = basename_fallback[[File.basename(logical_source), name]]
  matches.first if matches.length == 1
end

spec_index, basename_fallback = load_spec_index(root)
recent_id_set = last_run_ids(log_path, options[:recent_runs])
stats = {}
malformed = 0

File.foreach(log_path, encoding: Encoding::UTF_8) do |line|
  row = JSON.parse(line) rescue (malformed += 1; next)
  run_id, version, source_file, test_name, complexity, status = row
  next if recent_id_set && !recent_id_set[run_id]

  complexity = complexity.to_i
  logical = logical_source(source_file)
  key = [logical, test_name]
  item = stats[key] ||= Stats.new(
    logical_source: logical,
    name: test_name,
    complexity: complexity,
    total: 0,
    success: 0,
    fail: 0,
    error: 0,
    bad_runs: {},
    versions: Hash.new(0),
  )
  item.complexity = [item.complexity, complexity].min
  item.total += 1
  item.versions[version] += 1
  case status
  when "success"
    item.success += 1
  when "fail"
    item.fail += 1
    item.bad_runs[run_id] = true
  when "error"
    item.error += 1
    item.bad_runs[run_id] = true
  else
    item.error += 1
    item.bad_runs[run_id] = true
  end
end

ranked = stats.values
  .select { |s| s.bad >= options[:min_bad] }
  .select do |s|
    next true unless options[:max_complexity]

    info = find_spec_info(spec_index, basename_fallback, s.logical_source, s.name)
    (info&.complexity || s.complexity) <= options[:max_complexity]
  end
  .sort_by do |s|
    info = find_spec_info(spec_index, basename_fallback, s.logical_source, s.name)
    display_complexity = info&.complexity || s.complexity
    [-s.bad_runs.length, -s.bad, display_complexity, -s.fail_rate, s.logical_source, s.name]
  end
  .first(options[:top])

puts "Liquid-spec stuck-spec report"
puts "Log: #{log_path}"
puts "Scope: #{options[:recent_runs] ? "last #{options[:recent_runs]} distinct runs" : "all runs"}"
puts "Filters: min_bad=#{options[:min_bad]}#{options[:max_complexity] ? ", max_complexity=#{options[:max_complexity]}" : ""}"
puts "Malformed log lines skipped: #{malformed}" if malformed.positive?
puts "Specs indexed from: #{File.join(root, "specs")}" unless spec_index.empty?
puts ""

if ranked.empty?
  puts "No stuck specs matched."
  exit 0
end

ranked.each_with_index do |s, idx|
  info = find_spec_info(spec_index, basename_fallback, s.logical_source, s.name)

  spec_complexity = info&.complexity || s.complexity
  suggestion = if spec_complexity <= 220 && (info&.hint.nil? || info.hint.to_s.strip.empty?)
    "add hint"
  elsif s.fail_rate >= 0.80 && s.bad_runs.length >= 3
    "review hint or raise complexity"
  elsif s.error.positive? && s.fail.zero?
    "likely missing feature/runtime crash; improve implementation hint"
  else
    "review hint/complexity"
  end

  puts "%2d. c=%-4d bad_runs=%-3d bad=%-4d fail=%-4d error=%-4d pass=%-4d fail_rate=%5.1f%%  %s" % [
    idx + 1,
    spec_complexity,
    s.bad_runs.length,
    s.bad,
    s.fail,
    s.error,
    s.success,
    s.fail_rate * 100,
    s.name,
  ]
  puts "    source: #{s.logical_source}"
  puts "    candidate: #{suggestion}"

  if info
    puts "    template:    #{snippet(info.template) || "(none)"}"
    puts "    environment: #{snippet(info.environment)}" if info.environment
    if info.errors
      puts "    expected error: #{snippet(info.errors)}"
    else
      puts "    expected:    #{snippet(info.expected) || "(none)"}"
    end
    if info.hint && !info.hint.to_s.strip.empty?
      puts "    current hint: #{snippet(info.hint, 260)}"
    else
      puts "    current hint: (missing)"
    end
  else
    puts "    spec yaml:   not found in this checkout (source may be from another installed liquid-spec revision)"
  end
  puts ""
end
