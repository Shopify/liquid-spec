# frozen_string_literal: true

require "liquid/version"
require_relative "../lib/liquid/spec/adapter_runner"

module Helpers
  extend self

  def load_shopify_liquid
    git_tag = "v#{Liquid::VERSION}"

    FileUtils.mkdir_p("tmp")
    FileUtils.rm_rf("tmp/liquid")

    puts "Loading Shopify/liquid@#{git_tag}..."

    %x(git clone --depth 1 https://github.com/Shopify/liquid.git ./tmp/liquid)
    %x(git -C tmp/liquid checkout #{git_tag})
    insert_patch("tmp/liquid/Gemfile", "gem \"timecop\", \"~> 0.9.10\"\n")
    insert_patch("tmp/liquid/Gemfile", "gem \"activesupport\", \"~> 7.1\"\n")
    insert_patch("tmp/liquid/test/test_helper.rb", <<~RUBY)
      require "timecop"

      module TimeHooks
        TEST_TIME = Time.parse("#{Liquid::Spec::AdapterRunner::TEST_TIME.iso8601}")

        def before_setup
          super
          Timecop.freeze(TEST_TIME)
        end

        def after_teardown
          super
          Timecop.return
        end
      end

      Minitest::Test.prepend(TimeHooks)
    RUBY

    Bundler.with_unbundled_env do
      system("cd tmp/liquid && bundle install")
    end
  end

  def insert_patch(file_path, patch)
    contents = File.read(file_path)
    return if contents.include?(patch)

    # For gem declarations, check if gem is already declared (any version)
    if patch =~ /\Agem ["'](\w+)['"]/
      gem_name = $1
      return if contents =~ /gem\s+["']#{Regexp.escape(gem_name)}["']/
    end

    File.write(file_path, patch, mode: "a+")
  end

  def reset_captures(path)
    File.delete(path) if File.exist?(path)
    File.write(path, "---\n", mode: "a+")
  end

  def format_and_write_specs(capture_path, outfile)
    yaml = File.read(capture_path)
    data = YAML.safe_load(yaml, permitted_classes: [Symbol, Date, Time], aliases: true)

    data.each { |spec| annotate_required_features!(spec) }
    data.sort_by! { |h| h["name"] }
    data.uniq!

    outfile = File.expand_path(outfile)
    puts "Writing #{data.size} tests to #{outfile}..."
    File.write(outfile, YAML.dump(data))
  end

  private

  # Auto-detect required_features based on environment content.
  # - ruby_drops: environment uses instantiate: (Drop objects)
  # - ruby_types: environment has integer keys or symbol keys
  def annotate_required_features!(spec)
    features = []

    env = spec["environment"]
    if env
      features << "ruby_drops" if env.inspect.include?("instantiate:")
      features << "ruby_types" if has_ruby_type_usage?(env)
    end

    spec["required_features"] = features unless features.empty?
  end

  def has_ruby_type_usage?(value, depth: 0)
    return false if depth > 5

    case value
    when Hash
      value.each do |k, v|
        return true if k.is_a?(Integer) || k.is_a?(Symbol)
        return true if has_ruby_type_usage?(v, depth: depth + 1)
      end
    when Array
      value.each { |v| return true if has_ruby_type_usage?(v, depth: depth + 1) }
    end
    false
  end
end
