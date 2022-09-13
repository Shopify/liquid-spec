require 'json'
require 'digest'

class DecoratingFileSystem
  attr_reader :map, :inner

  def initialize(fs)
    @inner = fs
    @map = {}
  end

  def read_template_file(template_path)
    @map[template_path] = @inner.read_template_file(template_path)
  end
end

CAPTURE_PATH = File.join(__dir__, "..", "..", "..", "..", "tmp", "liquid-ruby-capture.yml")
module ShopifyLiquidPatch
  def assert_template_result(expected, template, assigns = {}, message = nil)
    data = {
      "template" => template,
      "environment" => _deep_dup(assigns),
      "expected" => expected,
      "name" => "#{class_name}##{name}",
    }

    unless Liquid::Template.file_system.is_a?(Liquid::BlankFileSystem)
      Liquid::Template.file_system = DecoratingFileSystem.new(Liquid::Template.file_system)
    end

    result = super
  ensure
    if result
      fs = Liquid::Template.file_system
      unless fs.is_a?(Liquid::BlankFileSystem)
        data["filesystem"] = fs.map unless fs.map.empty?
        Liquid::Template.file_system = fs.inner
      end

      digest = Digest::MD5.hexdigest(YAML.dump(data))
      data["name"] = "#{data["name"]}_#{digest}"
      test_data = caller
        .select { |line| line.match(%r{liquid-spec/tmp/liquid/test/.*_test\.rb}) }
        .first
        .match(%r{liquid-spec/tmp/liquid/(?<filename>test/.+\.rb):(?<lineno>\d+)})
      git_revision = `git rev-parse HEAD`.chomp
      data["url"] = "https://github.com/Shopify/liquid/blob/#{git_revision}/#{test_data[:filename]}#L#{test_data[:lineno]}"

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
  end

  def _deep_dup(env)
    if env.is_a?(Hash)
      new_env = {}
      env.each do |k, v|
        new_env[k] = _deep_dup(v)
      end
      new_env
    elsif env.is_a?(Array)
      new_env = []
      env.each do |v|
        new_env << _deep_dup(v)
      end
      new_env
    else
      env.dup
    end
  end
end

Minitest::Test.prepend(ShopifyLiquidPatch)
