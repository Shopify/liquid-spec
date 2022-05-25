require 'json'
require 'digest'

CAPTURE_PATH = File.join(__dir__, "..", "..", "..", "..", "tmp", "liquid-ruby-capture.yml")
module ShopifyLiquidPatch
  def assert_template_result(expected, template, assigns = {}, message = nil)
    if message.nil?
      name = caller
        .select { |line| line.match(%r{liquid-spec/tmp/liquid/test/.*_test\.rb}) }
        .first
        .match(/_test.rb:\d+:in `(?<name>\w+)/)[:name]

      data = {
        "template" => template,
        "environment" => assigns,
        "expected" => expected,
        "name" => name,
      }

      unless Liquid::Template.file_system.is_a?(Liquid::BlankFileSystem)
        data["filesystem"] = Liquid::Template.file_system
      end

      digest = Digest::MD5.hexdigest(YAML.dump(data))
      # require 'pry-byebug'
      # binding.pry
      data["name"] = "#{name}_#{digest}"

      yaml = YAML.dump(data)
      if yaml.include?("!ruby/object:Proc")
        puts "\n=============== Skipped ==============="
        puts yaml
        puts "=======================================\n"
      else
        File.write(
          CAPTURE_PATH,
          "- #{yaml[4..].gsub("\n", "\n  ").rstrip.chomp("...").rstrip}\n",
          mode: "a+"
        )
      end
    end

    super
  end
end

Minitest::Test.prepend(ShopifyLiquidPatch)
