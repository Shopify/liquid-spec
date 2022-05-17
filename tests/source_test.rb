require "test_helper"

class SourceTest < Minitest::Test
  MOCK_YAML = <<~YAML
    ---
    - template: "{% assign 123 = 'bar' %}{{ 123 }}"
      environment: {}
      expected: '123'
  YAML

  def test_yaml_source_works
    path = "fake.yml"

    File.expects(:read).with(path).returns(MOCK_YAML).once
    runner = Liquid::Spec::Source.for(path)
    expected = [{
      "template" => "{% assign 123 = 'bar' %}{{ 123 }}",
      "environment" => {},
      "expected" => "123",
    }]

    assert_equal(expected, runner.to_a)
  end
end
