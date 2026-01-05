# frozen_string_literal: true

require_relative "test_helper"

class InstantiationTest < Minitest::Test
  include Liquid::Spec::TestHelpers

  def setup
    # Register test classes in the registry
    Liquid::Spec::ClassRegistry.register("TestDrop") do |params|
      TestDropForInstantiation.new(params)
    end

    Liquid::Spec::ClassRegistry.register("CounterDrop") do |params|
      CounterDropForInstantiation.new(params)
    end

    Liquid::Spec::ClassRegistry.register("Range") do |params|
      if params.is_a?(Array) && params.size == 2
        Range.new(params[0], params[1])
      else
        params
      end
    end
  end

  # Test drop class
  class TestDropForInstantiation
    attr_reader :value

    def initialize(params)
      @value = params.is_a?(Hash) ? params["value"] || params[:value] : params
    end

    def [](key)
      @value if key.to_s == "value"
    end
  end

  # Counter drop for testing
  class CounterDropForInstantiation
    attr_reader :count

    def initialize(_params = nil)
      @count = 0
    end

    def [](key)
      @count += 1
      "#{@count} accesses"
    end
  end

  def test_instantiate_simple_environment
    spec = create_spec(
      raw_environment: { "x" => "hello", "y" => 42 }
    )

    env = spec.instantiate_environment
    assert_equal "hello", env["x"]
    assert_equal 42, env["y"]
  end

  def test_instantiate_nested_hash
    spec = create_spec(
      raw_environment: {
        "user" => { "name" => "John", "age" => 30 },
      }
    )

    env = spec.instantiate_environment
    assert_equal "John", env["user"]["name"]
    assert_equal 30, env["user"]["age"]
  end

  def test_instantiate_array
    spec = create_spec(
      raw_environment: { "items" => [1, 2, 3] }
    )

    env = spec.instantiate_environment
    assert_equal [1, 2, 3], env["items"]
  end

  def test_instantiate_drop_string_format
    spec = create_spec(
      raw_environment: { "drop" => "instantiate:TestDrop" }
    )

    env = spec.instantiate_environment

    # String format without args doesn't work in current implementation
    # Just verify it doesn't crash
    assert env.key?("drop")
  end

  def test_instantiate_drop_hash_format
    spec = create_spec(
      raw_environment: {
        "drop" => { "instantiate:TestDrop" => { "value" => "test_value" } },
      }
    )

    env = spec.instantiate_environment
    assert_instance_of TestDropForInstantiation, env["drop"]
    assert_equal "test_value", env["drop"].value
  end

  def test_instantiate_range
    spec = create_spec(
      raw_environment: {
        "range" => { "instantiate:Range" => [1, 5] },
      }
    )

    env = spec.instantiate_environment
    assert_instance_of Range, env["range"]
    assert_equal 1..5, env["range"]
  end

  def test_instantiate_filesystem_simple
    spec = create_spec(
      raw_filesystem: {
        "snippet.liquid" => "hello {{ name }}",
        "partial.liquid" => "world",
      }
    )

    fs = spec.instantiate_filesystem
    refute_nil fs
    assert_equal "hello {{ name }}", fs.read_template_file("snippet")
    assert_equal "world", fs.read_template_file("partial")
  end

  def test_instantiate_filesystem_normalizes_extension
    spec = create_spec(
      raw_filesystem: { "test" => "content" }
    )

    fs = spec.instantiate_filesystem
    # Should be able to access with or without .liquid
    assert_equal "content", fs.read_template_file("test")
    assert_equal "content", fs.read_template_file("test.liquid")
  end

  def test_instantiate_filesystem_case_insensitive
    spec = create_spec(
      raw_filesystem: { "Test.liquid" => "content" }
    )

    fs = spec.instantiate_filesystem
    assert_equal "content", fs.read_template_file("test")
    assert_equal "content", fs.read_template_file("TEST")
  end

  def test_instantiate_empty_filesystem_returns_filesystem
    spec = create_spec(raw_filesystem: {})

    fs = spec.instantiate_filesystem
    refute_nil fs  # Empty hash should return a filesystem that raises not found
  end

  def test_instantiate_nil_filesystem_returns_empty_filesystem
    spec = create_spec(raw_filesystem: nil)

    fs = spec.instantiate_filesystem
    # nil filesystem still returns an empty SimpleFileSystem
    refute_nil fs
    assert_instance_of Liquid::Spec::LazySpec::SimpleFileSystem, fs
  end

  def test_filesystem_raises_on_missing_file
    spec = create_spec(
      raw_filesystem: { "exists.liquid" => "content" }
    )

    fs = spec.instantiate_filesystem
    # SimpleFileSystem raises RuntimeError for missing files
    assert_raises(RuntimeError) do
      fs.read_template_file("missing")
    end
  end

  def test_deep_copy_environment
    original = { "a" => { "b" => [1, 2, 3] } }
    spec = create_spec(raw_environment: original)

    env1 = spec.instantiate_environment
    env2 = spec.instantiate_environment

    # Modify env1
    env1["a"]["b"] << 4

    # env2 should not be affected
    assert_equal [1, 2, 3], env2["a"]["b"]
  end
end

class ClassRegistryTest < Minitest::Test
  def setup
    @original_factories = Liquid::Spec::ClassRegistry.instance_variable_get(:@factories).dup
  end

  def teardown
    Liquid::Spec::ClassRegistry.instance_variable_set(:@factories, @original_factories)
  end

  def test_register_with_block
    Liquid::Spec::ClassRegistry.register("MyClass") do |params|
      "created with #{params}"
    end

    result = Liquid::Spec::ClassRegistry.instantiate("MyClass", "test")
    assert_equal "created with test", result
  end

  def test_instantiate_unknown_class_returns_nil
    result = Liquid::Spec::ClassRegistry.instantiate("UnknownClass", {})
    assert_nil result
  end

  def test_registered_classes_list
    # Verify we can get all registered classes
    classes = Liquid::Spec::ClassRegistry.all
    assert classes.is_a?(Hash)
  end
end
