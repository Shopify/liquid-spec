# frozen_string_literal: true

require_relative "test_helper"
require "json"

class JsonRpcProtocolTest < Minitest::Test
  Protocol = Liquid::Spec::JsonRpc::Protocol

  def test_request_format
    msg = Protocol.request(id: 1, method: "compile", params: { template: "test" })

    assert_equal "2.0", msg["jsonrpc"]
    assert_equal 1, msg["id"]
    assert_equal "compile", msg["method"]
    assert_equal({ template: "test" }, msg["params"])
  end

  def test_response_format
    msg = Protocol.response(id: 1, result: { template_id: "abc" })

    assert_equal "2.0", msg["jsonrpc"]
    assert_equal 1, msg["id"]
    assert_equal({ template_id: "abc" }, msg["result"])
  end

  def test_error_response_format
    msg = Protocol.error_response(
      id: 1,
      code: -32000,
      message: "Parse error",
      data: { line: 1 }
    )

    assert_equal "2.0", msg["jsonrpc"]
    assert_equal 1, msg["id"]
    assert_equal(-32000, msg["error"]["code"])
    assert_equal "Parse error", msg["error"]["message"]
    assert_equal({ line: 1 }, msg["error"]["data"])
  end

  def test_encode_decode_roundtrip
    original = Protocol.request(id: 42, method: "test", params: { x: 1 })
    encoded = Protocol.encode(original)
    decoded = Protocol.decode(encoded)

    # JSON roundtrip converts symbol keys to strings
    expected = { "jsonrpc" => "2.0", "id" => 42, "method" => "test", "params" => { "x" => 1 } }
    assert_equal expected, decoded
  end

  def test_decode_invalid_json_raises
    assert_raises(Liquid::Spec::JsonRpc::ProtocolError) do
      Protocol.decode("not valid json")
    end
  end

  def test_request_predicate
    request = Protocol.request(id: 1, method: "test", params: {})
    response = Protocol.response(id: 1, result: {})

    assert Protocol.request?(request)
    refute Protocol.request?(response)
  end

  def test_response_predicate
    request = Protocol.request(id: 1, method: "test", params: {})
    response = Protocol.response(id: 1, result: {})
    error = Protocol.error_response(id: 1, code: -1, message: "err")

    refute Protocol.response?(request)
    assert Protocol.response?(response)
    assert Protocol.response?(error)
  end

  def test_error_predicate
    response = Protocol.response(id: 1, result: {})
    error = Protocol.error_response(id: 1, code: -1, message: "err")

    refute Protocol.error?(response)
    assert Protocol.error?(error)
  end

  def test_extract_error
    error_msg = Protocol.error_response(
      id: 1,
      code: -32000,
      message: "Parse error",
      data: { type: "parse_error", line: 5 }
    )

    error = Protocol.extract_error(error_msg)
    assert_equal(-32000, error[:code])
    assert_equal "Parse error", error[:message]
    assert_equal({ type: "parse_error", line: 5 }, error[:data])
  end
end

class JsonRpcDropProxyTest < Minitest::Test
  DropProxy = Liquid::Spec::JsonRpc::DropProxy
  DropRegistry = Liquid::Spec::JsonRpc::DropRegistry

  def setup
    @registry = DropRegistry.new
  end

  def test_registry_assigns_unique_ids
    obj1 = Object.new
    obj2 = Object.new

    id1 = @registry.register(obj1)
    id2 = @registry.register(obj2)

    refute_equal id1, id2
    assert_equal obj1, @registry[id1]
    assert_equal obj2, @registry[id2]
  end

  def test_registry_clear
    @registry.register(Object.new)
    @registry.register(Object.new)

    assert_equal 2, @registry.size

    @registry.clear

    assert_equal 0, @registry.size
  end

  def test_wrap_primitives
    assert_equal "hello", DropProxy.wrap("hello", @registry)
    assert_equal 42, DropProxy.wrap(42, @registry)
    assert_equal 3.14, DropProxy.wrap(3.14, @registry)
    assert_equal true, DropProxy.wrap(true, @registry)
    assert_equal false, DropProxy.wrap(false, @registry)
    assert_nil DropProxy.wrap(nil, @registry)
  end

  def test_wrap_symbol_to_string
    assert_equal "test", DropProxy.wrap(:test, @registry)
  end

  def test_wrap_hash
    input = { "a" => 1, "b" => "hello" }
    result = DropProxy.wrap(input, @registry)

    assert_equal({ "a" => 1, "b" => "hello" }, result)
  end

  def test_wrap_hash_with_symbol_keys
    input = { a: 1, b: "hello" }
    result = DropProxy.wrap(input, @registry)

    assert_equal({ "a" => 1, "b" => "hello" }, result)
  end

  def test_wrap_array
    input = [1, "hello", true]
    result = DropProxy.wrap(input, @registry)

    assert_equal [1, "hello", true], result
  end

  def test_wrap_range_to_array
    input = 1..5
    result = DropProxy.wrap(input, @registry)

    assert_equal [1, 2, 3, 4, 5], result
  end

  def test_wrap_drop_creates_rpc_marker
    drop = TestDrop.new("value")
    result = DropProxy.wrap(drop, @registry)

    assert result.is_a?(Hash)
    assert result.key?("_rpc_drop")
    assert result.key?("type")
    assert_equal "JsonRpcDropProxyTest::TestDrop", result["type"]
  end

  def test_rpc_drop_predicate
    assert DropProxy.rpc_drop?({ "_rpc_drop" => "drop_1" })
    refute DropProxy.rpc_drop?({ "regular" => "hash" })
    refute DropProxy.rpc_drop?("string")
  end

  def test_access_drop_with_brackets
    drop = TestDrop.new("test_value")
    result = DropProxy.access_drop(drop, "value")

    assert_equal "test_value", result
  end

  def test_call_drop_method
    drop = TestDrop.new("test")
    result = DropProxy.call_drop(drop, "upcase_value", [])

    assert_equal "TEST", result
  end

  def test_iterate_drop
    drop = IterableDrop.new([1, 2, 3])
    result = DropProxy.iterate_drop(drop)

    assert_equal [1, 2, 3], result
  end

  # Test drop class
  class TestDrop
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def [](key)
      @value if key.to_s == "value"
    end

    def upcase_value
      @value.to_s.upcase
    end

    def to_liquid
      self
    end
  end

  # Iterable drop class
  class IterableDrop
    def initialize(items)
      @items = items
    end

    def to_a
      @items
    end

    def to_liquid
      self
    end
  end
end

class JsonRpcMockServerTest < Minitest::Test
  MOCK_SERVER_PATH = File.expand_path("fixtures/mock_liquid_server.rb", __dir__)

  def setup
    skip "Mock server not found" unless File.exist?(MOCK_SERVER_PATH)
  end

  def test_adapter_compile_and_render
    adapter = Liquid::Spec::JsonRpc::Adapter.new("ruby #{MOCK_SERVER_PATH}")

    begin
      adapter.start

      # Compile
      template_id = adapter.compile("{{ x | upcase }}", {})
      refute_nil template_id

      # Render
      output = adapter.render(template_id, { "x" => "hello" }, {})
      assert_equal "HELLO", output
    ensure
      adapter.shutdown
    end
  end

  def test_adapter_parse_error
    adapter = Liquid::Spec::JsonRpc::Adapter.new("ruby #{MOCK_SERVER_PATH}")

    begin
      adapter.start

      assert_raises(Liquid::Spec::JsonRpc::LiquidParseError) do
        adapter.compile("{% invalid_tag %}", {})
      end
    ensure
      adapter.shutdown
    end
  end

  def test_adapter_render_error
    adapter = Liquid::Spec::JsonRpc::Adapter.new("ruby #{MOCK_SERVER_PATH}")

    begin
      adapter.start

      # Include without a filesystem triggers a render error
      template_id = adapter.compile("{% include 'nonexistent' %}", {})

      assert_raises(Liquid::Spec::JsonRpc::LiquidRenderError) do
        adapter.render(template_id, {}, {})
      end
    ensure
      adapter.shutdown
    end
  end

  def test_adapter_with_filesystem
    adapter = Liquid::Spec::JsonRpc::Adapter.new("ruby #{MOCK_SERVER_PATH}")

    begin
      adapter.start

      filesystem = Liquid::Spec::LazySpec::SimpleFileSystem.new({
        "snippet.liquid" => "Hello {{ name }}!",
      })

      template_id = adapter.compile(
        "{% include 'snippet' %}",
        { file_system: filesystem }
      )

      output = adapter.render(template_id, { "name" => "World" }, {})
      assert_equal "Hello World!", output
    ensure
      adapter.shutdown
    end
  end

  def test_adapter_with_drop_callback
    adapter = Liquid::Spec::JsonRpc::Adapter.new("ruby #{MOCK_SERVER_PATH}")

    begin
      adapter.start

      template_id = adapter.compile("{{ user.name }}", {})

      # Create a drop that will require RPC callback
      user_drop = UserDrop.new("Alice")
      output = adapter.render(template_id, { "user" => user_drop }, {})

      assert_equal "Alice", output
    ensure
      adapter.shutdown
    end
  end

  # Test drop for RPC callbacks
  class UserDrop
    def initialize(name)
      @name = name
    end

    def [](key)
      @name if key.to_s == "name"
    end

    def to_liquid
      self
    end
  end
end
