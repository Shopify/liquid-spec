require "test_helper"

class SourceTest < Minitest::Test
  MOCK_YAML = <<~YAML
    ---
    - template: "{% assign 123 = 'bar' %}{{ 123 }}"
      environment: {}
      expected: '123'
      name: "test_name"
      filesystem:
        foo: "bar"
  YAML

  def test_yaml_source_works
    path = "fake.yml"

    File.expects(:read).with(path).returns(MOCK_YAML).once
    runner = Liquid::Spec::Source.for(path)
    expected = [
      Liquid::Spec::Unit.new(
        template: "{% assign 123 = 'bar' %}{{ 123 }}",
        environment: {},
        expected: "123",
        name: "test_name",
        filesystem: { "foo" => "bar" },
      )
    ]

    assert_equal(expected, runner.to_a)
  end

  MOCK_TXT = <<~TXT
    ===
    NAME 2
    ===
    template: product
    product:
      title: Draft 151cm
    ___
    product: 'Product: {{ product.title }} '
    ---
    {% include template for product %}
    +++
    Product: Draft 151cm 
  TXT

  def test_text_source_works
    path = "fake.txt"

    File.expects(:read).with(path).returns(MOCK_TXT).once
    runner = Liquid::Spec::Source.for(path)
    expected = [
      Liquid::Spec::Unit.new(
        template: "{% include template for product %}",
        environment: {
          "template" => "product",
          "product" => { "title" => "Draft 151cm" },
        },
        expected: "Product: Draft 151cm ",
        name: "NAME_2",
        filesystem: {
          "product" => 'Product: {{ product.title }} '
        },
      )
    ]

    assert_equal(expected, runner.to_a)
  end
end
