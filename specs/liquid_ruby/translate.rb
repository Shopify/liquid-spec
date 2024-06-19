require 'liquid'
require_relative '../../lib/liquid/spec/deps/liquid_ruby'
require 'yaml'

def underscore(str)
  str.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
end

def reformat_specs(specs)
  specs.reduce({}) do |acc, spec|
    t = spec.fetch('template')
    e = spec.fetch('expected')
    c = spec.fetch('environment', {})
    f = spec.fetch('filesystem', {})
    test_name = spec.fetch('name').split('#').last.sub(/^test_/, '').sub(/_[a-f0-9]+$/, '').gsub('_', ' ')
    new_spec = { 'TPL' => t, 'EXP' => e }
    new_spec['CTX'] = c if c.any?
    new_spec['FSS'] = f if f.any?
    if f.empty? && c.empty? && t.length + e.length < 80
      new_spec = { t => e }
    end
    acc.merge(test_name => [*acc.fetch(test_name, []), new_spec])
  end
end

def ugh(pn)
  specs = YAML.unsafe_load(File.read(pn))

  by_testfile = {}
  specs.each do |spec|
    test_file = spec['name'].split('#').first
    by_testfile[test_file] ||= []
    by_testfile[test_file] << spec
  end

  by_testfile.each do |test_file, specs|
    subject = test_file.sub(/Test$/, '')
    base = underscore(subject)
    fname = "out/#{base}.yml"

    data = { subject => reformat_specs(specs) }

    File.write(fname, YAML.dump(data, line_width: -1))
  end
end

ugh('specs.yml')
ugh('standard_filters.yml')
