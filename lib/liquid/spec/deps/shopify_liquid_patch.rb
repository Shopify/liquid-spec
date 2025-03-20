# frozen_string_literal: true

require "json"
require "digest"

CAPTURE_PATH = File.join(__dir__, "..", "..", "..", "..", "tmp", "liquid-ruby-capture.yml")
module ShopifyLiquidPatch
  def assert_template_result(expected, template, assigns = {},
    message: nil, partials: nil, error_mode: nil, render_errors: false, template_factory: nil)
    data = {
      "template" => template,
      "environment" => _deep_dup(assigns),
      "error_mode" => error_mode,
      "render_errors" => render_errors,
      "message" => message,
      "expected" => expected,
    }

    if template_factory
      data["template_factory"] = template_factory
    end

    data.delete("environment") if assigns.empty?
    data["filesystem"] = partials if partials

    result = super

    if result
      digest = Digest::SHA256.new
      digest << template
      digest << data.to_s
      digest = digest.hexdigest[0..7]
      test_name = "#{class_name}##{name}_#{digest}"
      data = { "name" => test_name }.merge(data).compact
      test_data = caller
        .select { |line| line.match(%r{liquid-spec/tmp/liquid/test/.*_test\.rb}) }
        .first
        .match(%r{liquid-spec/tmp/liquid/(?<filename>test/.+\.rb):(?<lineno>\d+)})
      git_revision = %x(git rev-parse HEAD).chomp
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
          mode: "a+",
        )
      end
    end

    result
  end

  def _deep_dup(env)
    Marshal.load(Marshal.dump(env))
  end
end

Minitest::Test.prepend(ShopifyLiquidPatch)
