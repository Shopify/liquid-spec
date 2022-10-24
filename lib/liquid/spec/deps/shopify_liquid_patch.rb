require 'json'
require 'digest'

CAPTURE_PATH = File.join(__dir__, "..", "..", "..", "..", "tmp", "liquid-ruby-capture.yml")
module ShopifyLiquidPatch
  def assert_template_result(expected, template, assigns = {},
    message: nil, partials: nil, error_mode: nil, render_errors: false
  )
    data = {
      "template" => template,
      "environment" => _deep_dup(assigns),
      "expected" => expected,
      "name" => "#{class_name}##{name}",
    }
    data.delete("environment") if assigns.empty?
    data["filesystem"] = partials if partials

    result = super
  ensure
    if result
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
