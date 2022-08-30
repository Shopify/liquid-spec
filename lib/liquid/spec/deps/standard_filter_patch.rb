require 'digest'

module StandardFilterPatch
  extend self

  CAPTURE_PATH = File.join(__dir__, "..", "..", "..", "..", "tmp", "standard-filters-capture.yml")

  def generate_spec(filter_name, result, *args)
    data = {
      "template" => build_liquid(args, filter_name),
      "environment" => build_environtment(args),
      "expected" => build_expected(result),
      "name" => "StandardFilterTest##{test_name}",
    }
    digest = Digest::MD5.hexdigest(YAML.dump(data))
    data["name"] = "#{data["name"]}_#{digest}"
    yaml = YAML.dump(data)
    return if digest =~ /7e18eb50bc2c00e0934edd8a3ec8deb3/
    binding.irb if yaml.include?("Proc")
    File.write(
      CAPTURE_PATH,
      "- #{yaml[4..].gsub("\n", "\n  ").rstrip.chomp("...").rstrip}\n",
      mode: "a+"
    )
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
    elsif env.is_a?(Liquid::Drop)
      env.context = {}
      env.dup
    elsif env.is_a?(TestThing)
      env.instance_eval { @foo -= 1 }
      env.dup
    else
      env.dup
    end
  end

  private

  def build_liquid(input, filter_name)
    if input.size == 1
      <<~LIQUID.strip
        {{ foo0 | #{filter_name} }}
      LIQUID
    elsif input.size == 2
      <<~LIQUID.strip
        {{ foo0 | #{filter_name}: #{format_args(input.last(1))} }}
      LIQUID
    else
      <<~LIQUID.strip
        {{ foo0 | #{filter_name}: #{format_args(input[1..])} }}
      LIQUID
    end
  end

  def format_args(args)
    args.map.with_index do |arg, i|
      if arg.is_a?(String)
        arg.inspect 
      elsif arg.is_a?(Hash)
        raise if arg.size != 1
        "#{arg.keys.first}: #{format_args(arg.values)}"
      elsif arg.is_a?(Array)
        "foo#{i + 1}"
      elsif arg.nil?
        "foo#{i + 1}"
      else
        arg.to_s
      end
    end.join(", ")
  end

  def build_environtment(args)
    args.each_with_object({}).with_index do |(arg, env), i|
      env["foo#{i}"] = _deep_dup(arg)
    end
  end

  def build_expected(result)
    if result.is_a?(Array)
      result.join
    elsif result.is_a?(Numeric)
      result.to_s
    elsif result.nil?
      ""
    elsif result.is_a?(String)
      result
    elsif result.is_a?(TrueClass) || result.is_a?(FalseClass)
      result.to_s
    elsif result.is_a?(Hash)
      result.to_s
    elsif result.is_a?(Liquid::Drop)
      result.to_s
    else
      result.to_s
    end
  end

  def test_name
    match = caller
      .select { |l| l.match(%r{test/integration/standard_filter_test.rb} ) }
      .last
      .match(/\.rb:(?<lineno>\d+):in `(?<test_name>test_\w+).$/)
    "#{match[:test_name]}:#{match[:lineno]}"
  end
end
