# frozen_string_literal: true

require_relative "test_helper"

# Integration test for JSON-RPC adapter against a real Liquid implementation
class JsonRpcIntegrationTest < Minitest::Test
  SERVER_PATH = File.expand_path("implementations/liquid_jsonrpc_server.rb", __dir__)

  # Simple drop helper for testing drop callbacks
  class SimpleDrop
    def initialize(**attrs)
      @attrs = attrs.transform_keys(&:to_s)
    end

    def [](key)
      @attrs[key.to_s]
    end

    def to_liquid
      self
    end
  end

  def setup
    skip "Server not found at #{SERVER_PATH}" unless File.exist?(SERVER_PATH)
    @adapter = Liquid::Spec::JsonRpc::Adapter.new("bundle exec ruby #{SERVER_PATH}")
    @adapter.start
  end

  def teardown
    @adapter&.shutdown
  end

  # Basic output tests
  def test_raw_text_output
    template_id = @adapter.compile("Hello World")
    output = @adapter.render(template_id, {})
    assert_equal "Hello World", output
  end

  def test_variable_output
    template_id = @adapter.compile("Hello {{ name }}!")
    output = @adapter.render(template_id, { "name" => "World" })
    assert_equal "Hello World!", output
  end

  def test_nested_variable_access
    template_id = @adapter.compile("{{ user.name }}")
    output = @adapter.render(template_id, { "user" => { "name" => "Alice" } })
    assert_equal "Alice", output
  end

  # Filter tests
  def test_upcase_filter
    template_id = @adapter.compile("{{ name | upcase }}")
    output = @adapter.render(template_id, { "name" => "hello" })
    assert_equal "HELLO", output
  end

  def test_downcase_filter
    template_id = @adapter.compile("{{ name | downcase }}")
    output = @adapter.render(template_id, { "name" => "HELLO" })
    assert_equal "hello", output
  end

  def test_filter_chain
    template_id = @adapter.compile("{{ name | upcase | append: '!' }}")
    output = @adapter.render(template_id, { "name" => "hello" })
    assert_equal "HELLO!", output
  end

  def test_size_filter
    template_id = @adapter.compile("{{ items | size }}")
    output = @adapter.render(template_id, { "items" => [1, 2, 3, 4, 5] })
    assert_equal "5", output
  end

  # Control flow tests
  def test_if_true
    template_id = @adapter.compile("{% if show %}visible{% endif %}")
    output = @adapter.render(template_id, { "show" => true })
    assert_equal "visible", output
  end

  def test_if_false
    template_id = @adapter.compile("{% if show %}visible{% endif %}")
    output = @adapter.render(template_id, { "show" => false })
    assert_equal "", output
  end

  def test_if_else
    template_id = @adapter.compile("{% if show %}yes{% else %}no{% endif %}")
    output = @adapter.render(template_id, { "show" => false })
    assert_equal "no", output
  end

  def test_unless
    template_id = @adapter.compile("{% unless hidden %}visible{% endunless %}")
    output = @adapter.render(template_id, { "hidden" => false })
    assert_equal "visible", output
  end

  def test_case_when
    template_id = @adapter.compile("{% case color %}{% when 'red' %}R{% when 'green' %}G{% else %}X{% endcase %}")
    output = @adapter.render(template_id, { "color" => "green" })
    assert_equal "G", output
  end

  # Loop tests
  def test_for_loop
    template_id = @adapter.compile("{% for i in items %}{{ i }}{% endfor %}")
    output = @adapter.render(template_id, { "items" => [1, 2, 3] })
    assert_equal "123", output
  end

  def test_for_loop_with_forloop_index
    template_id = @adapter.compile("{% for i in items %}{{ forloop.index }}{% endfor %}")
    output = @adapter.render(template_id, { "items" => %w[a b c] })
    assert_equal "123", output
  end

  def test_for_loop_with_limit
    template_id = @adapter.compile("{% for i in items limit:2 %}{{ i }}{% endfor %}")
    output = @adapter.render(template_id, { "items" => [1, 2, 3, 4, 5] })
    assert_equal "12", output
  end

  def test_for_loop_with_offset
    template_id = @adapter.compile("{% for i in items offset:2 %}{{ i }}{% endfor %}")
    output = @adapter.render(template_id, { "items" => [1, 2, 3, 4, 5] })
    assert_equal "345", output
  end

  def test_for_loop_range
    template_id = @adapter.compile("{% for i in (1..3) %}{{ i }}{% endfor %}")
    output = @adapter.render(template_id, {})
    assert_equal "123", output
  end

  def test_for_loop_with_break
    template_id = @adapter.compile("{% for i in (1..5) %}{% if i == 3 %}{% break %}{% endif %}{{ i }}{% endfor %}")
    output = @adapter.render(template_id, {})
    assert_equal "12", output
  end

  def test_for_loop_with_continue
    template_id = @adapter.compile("{% for i in (1..5) %}{% if i == 3 %}{% continue %}{% endif %}{{ i }}{% endfor %}")
    output = @adapter.render(template_id, {})
    assert_equal "1245", output
  end

  # Assignment tests
  def test_assign
    template_id = @adapter.compile("{% assign x = 'hello' %}{{ x }}")
    output = @adapter.render(template_id, {})
    assert_equal "hello", output
  end

  def test_capture
    template_id = @adapter.compile("{% capture greeting %}Hello {{ name }}{% endcapture %}{{ greeting }}!")
    output = @adapter.render(template_id, { "name" => "World" })
    assert_equal "Hello World!", output
  end

  def test_increment
    template_id = @adapter.compile("{% increment counter %}{% increment counter %}{% increment counter %}")
    output = @adapter.render(template_id, {})
    assert_equal "012", output
  end

  def test_decrement
    template_id = @adapter.compile("{% decrement counter %}{% decrement counter %}{% decrement counter %}")
    output = @adapter.render(template_id, {})
    assert_equal "-1-2-3", output
  end

  # Comment and raw tests
  def test_comment
    template_id = @adapter.compile("before{% comment %}ignored{% endcomment %}after")
    output = @adapter.render(template_id, {})
    assert_equal "beforeafter", output
  end

  def test_raw
    template_id = @adapter.compile("{% raw %}{{ not_parsed }}{% endraw %}")
    output = @adapter.render(template_id, {})
    assert_equal "{{ not_parsed }}", output
  end

  # Filesystem tests
  def test_include_with_filesystem
    filesystem = { "greeting.liquid" => "Hello {{ name }}!" }
    template_id = @adapter.compile("{% include 'greeting' %}", { file_system: filesystem })
    output = @adapter.render(template_id, { "name" => "World" })
    assert_equal "Hello World!", output
  end

  def test_render_with_filesystem
    filesystem = { "card.liquid" => "{{ title }}: ${{ price }}" }
    template_id = @adapter.compile("{% render 'card', title: product.title, price: product.price %}", { file_system: filesystem })
    output = @adapter.render(template_id, { "product" => { "title" => "Widget", "price" => 99 } })
    assert_equal "Widget: $99", output
  end

  def test_nested_includes
    filesystem = {
      "outer.liquid" => "OUTER[{% include 'inner' %}]",
      "inner.liquid" => "INNER({{ value }})",
    }
    template_id = @adapter.compile("{% include 'outer' %}", { file_system: filesystem })
    output = @adapter.render(template_id, { "value" => "test" })
    assert_equal "OUTER[INNER(test)]", output
  end

  # Error handling tests
  def test_parse_error_for_invalid_syntax
    error = assert_raises(Liquid::Spec::JsonRpc::LiquidParseError) do
      @adapter.compile("{% invalid_tag %}")
    end
    assert_match(/parse|syntax|tag/i, error.message)
  end

  def test_render_error_for_missing_include
    template_id = @adapter.compile("{% include 'nonexistent' %}")
    error = assert_raises(Liquid::Spec::JsonRpc::LiquidRenderError) do
      @adapter.render(template_id, {})
    end
    assert_match(/nonexistent|not found|template/i, error.message)
  end

  # Drop callback tests
  def test_drop_property_access
    template_id = @adapter.compile("{{ user.name }}")
    user = SimpleDrop.new(name: "Alice", email: "alice@example.com")
    output = @adapter.render(template_id, { "user" => user })
    assert_equal "Alice", output
  end

  def test_drop_multiple_properties
    template_id = @adapter.compile("{{ user.name }} <{{ user.email }}>")
    user = SimpleDrop.new(name: "Bob", email: "bob@example.com")
    output = @adapter.render(template_id, { "user" => user })
    assert_equal "Bob <bob@example.com>", output
  end

  def test_nested_drop_access
    template_id = @adapter.compile("{{ company.owner.name }}")
    owner = SimpleDrop.new(name: "Carol")
    company = SimpleDrop.new(owner: owner)
    output = @adapter.render(template_id, { "company" => company })
    assert_equal "Carol", output
  end

  # Multiple template tests
  def test_multiple_templates
    id1 = @adapter.compile("Template 1: {{ x }}")
    id2 = @adapter.compile("Template 2: {{ x }}")

    out1 = @adapter.render(id1, { "x" => "A" })
    out2 = @adapter.render(id2, { "x" => "B" })

    assert_equal "Template 1: A", out1
    assert_equal "Template 2: B", out2
  end

  def test_rerender_same_template
    template_id = @adapter.compile("{{ greeting }}")

    out1 = @adapter.render(template_id, { "greeting" => "Hello" })
    out2 = @adapter.render(template_id, { "greeting" => "Goodbye" })

    assert_equal "Hello", out1
    assert_equal "Goodbye", out2
  end

  # Whitespace handling
  def test_whitespace_control
    template_id = @adapter.compile("{%- assign x = 'test' -%}{{ x }}")
    output = @adapter.render(template_id, {})
    assert_equal "test", output
  end
end
