# frozen_string_literal: true

require "digest"

module StandardFilterPatch
  extend self

  CAPTURE_PATH = File.join(__dir__, "..", "..", "..", "..", "tmp", "standard-filters-capture.yml")

  def generate_spec(filter_name, result, *args)
    template = build_liquid(args, filter_name)
    environment = build_environment(args)
    data = {
      "name" => "StandardFilterTest##{test_name(filter_name, template, _deep_dup(environment))}",
      "template" => template,
      "environment" => environment,
      "expected" => build_expected(result),
      "error_mode" => nil,
    }.compact
    yaml = YAML.dump(data)

    File.write(
      CAPTURE_PATH,
      "- #{yaml[4..].gsub("\n", "\n  ").rstrip}\n",
      mode: "a+",
    )
  end

  def _deep_dup(env)
    Marshal.load(Marshal.dump(env))
  rescue
    # Fallback for unmarshalable (anonymous class objects)
    env
  end

  private

  def build_liquid(input, filter_name)
    if input.size == 1
      <<~LIQUID.strip
        {{ a0 | #{filter_name} }}
      LIQUID
    else
      <<~LIQUID.strip
        {{ a0 | #{filter_name}: #{format_args(input[1..])} }}
      LIQUID
    end
  end

  def format_args(args)
    maybe_keyword_args = nil

    if args.last.is_a?(Hash)
      maybe_keyword_args = args.pop
    end

    args = args.map.with_index do |_arg, i|
      "a#{i + 1}"
    end

    if maybe_keyword_args
      args << maybe_keyword_args.map do |key, value|
        "#{key}: #{value}"
      end
    end

    args.join(", ")
  end

  def build_environment(args)
    args.each_with_object({}).with_index do |(arg, env), i|
      if arg.is_a?(TestThing)
        arg.instance_variable_set(:@foo, arg.instance_variable_get(:@foo) - 1) # 🤢
      end

      env["a#{i}"] = arg
    end
  end

  PRINT_RESULT_TEMPLATE = Liquid::Template.parse("{{ result }}")

  def build_expected(result)
    PRINT_RESULT_TEMPLATE.render!("result" => result)
  end

  def test_name(filter_name, template, environment)
    digest = Digest::SHA256.new
    digest << filter_name
    digest << template
    digest << environment.to_s
    digest = digest.hexdigest

    "test_#{filter_name}_#{digest[0..7]}"
  end
end
