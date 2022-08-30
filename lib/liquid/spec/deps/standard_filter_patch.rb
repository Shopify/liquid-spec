require 'digest'

module StandardFilterPatch
  extend self

  CAPTURE_PATH = File.join(__dir__, "..", "..", "..", "..", "tmp", "standard-filters-capture.yml")

  def generate_spec(filter_name, result, *args)
    return unless value_type?(result)
    data = {
      "template" => build_liquid(args, filter_name),
      "environment" => build_environment(args, result),
      "expected" => "",
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

  def value_type?(value)
    case value
    when Hash
      value.all? { |key, child| value_type?(child) }
    when Array
      value.all? { |item| value_type?(item) }
    when Integer, Float, String, BigDecimal, true, false, nil
      true
    when Liquid::Drop, TestThing, Enumerable
      false
    else
      raise "unexpected value type #{value.class}"
    end
  end

  def build_liquid(inputs, filter_name)
    liquid_args = ": #{format_args(inputs[1..])}" if inputs.length > 1
    assertion = "{% if expect != result %}expect != result\nexpect: {{expect}}\nresult: {{result}}{% endif %}"
    "{% assign result = input | #{filter_name}#{liquid_args} %}#{assertion}"
  end

  def format_args(args)
    args.map.with_index do |arg, i|
      if arg.is_a?(String)
        arg.inspect
      elsif arg.is_a?(Hash)
        raise if arg.size != 1
        "#{arg.keys.first}: #{format_args(arg.values)}"
      elsif arg.is_a?(Array)
        "arg#{i + 1}"
      elsif arg.nil?
        "arg#{i + 1}"
      else
        arg.to_s
      end
    end.join(", ")
  end

  def build_environment(args, result)
    env = {}
    args.each_with_index do |arg, i|
      name = i == 0 ? "input" : "arg#{i}"
      env[name] = _deep_dup(arg)
    end
    env["expect"] = _deep_dup(result)
    env
  end

  def test_name
    match = caller
      .select { |l| l.match(%r{test/integration/standard_filter_test.rb} ) }
      .last
      .match(/\.rb:(?<lineno>\d+):in `(?<test_name>test_\w+).$/)
    "#{match[:test_name]}:#{match[:lineno]}"
  end
end
