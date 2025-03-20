# frozen_string_literal: true

require "liquid/version"
require "liquid/spec/adapter/liquid_ruby"

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
        TEST_TIME = Time.parse("#{Liquid::Spec::Adapter::LiquidRuby::TEST_TIME.iso8601}")

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
    return if File.read(file_path).include?(patch)

    File.write(file_path, patch, mode: "a+")
  end

  def reset_captures(path)
    if File.exist?(path)
      File.delete(path)
      File.write(path, "---\n", mode: "a+")
    end
  end

  def format_and_write_specs(capture_path, outfile)
    yaml = File.read(capture_path)
    data = YAML.unsafe_load(yaml)
    data.sort_by! { |h| h["name"] }
    data.uniq!
    outfile = File.expand_path(outfile)
    puts "Writing #{data.size} tests to #{outfile}..."
    File.write(outfile, YAML.dump(data))
  end
end
