require "test_helper"

class SourceTest < Minitest::Test
  MOCK_YAML = <<~YAML
    ---
    Fake:
    - TPL: "{% assign 123 = 'bar' %}{{ 123 }}"
      CTX: {}
      EXP: '123'
      FSS:
        foo: "bar"
  YAML

  def test_yaml_source_works
    path = File.expand_path("fake.yml")

    File.expects(:read).with(path).returns(MOCK_YAML).once
    runner = Liquid::Spec::Source.for(path)
    expected = [
      Liquid::Spec::Unit.new(
        template: "{% assign 123 = 'bar' %}{{ 123 }}",
        environment: {},
        expected: "123",
        name: "[lax] Fake",
        filesystem: { "foo" => "bar" },
        error_mode: :lax,
        context_klass: Liquid::Context,
        file: path,
        line: 2,
      ),
      Liquid::Spec::Unit.new(
        template: "{% assign 123 = 'bar' %}{{ 123 }}",
        environment: {},
        expected: "123",
        name: "[strict] Fake",
        filesystem: { "foo" => "bar" },
        error_mode: :strict,
        context_klass: Liquid::Context,
        file: path,
        line: 2,
      )
    ]

    assert_equal(expected, runner.to_a)
  end

  def test_failure_message
    spec = Liquid::Spec::Unit.new(
      template: "{{ foo | capitalize }}",
      environment: { "foo" => "bar baz" },
      expected: "BAR BAZ",
      name: "test_name",
      filesystem: { "foo" => "bar" },
    )

    failure_message = Liquid::Spec::FailureMessage.new(spec, "BAR baz", width: 30)

    assert_includes failure_message.to_s, "{{ foo | capitalize }}"
    assert_includes failure_message.to_s, '{"foo"=>"bar baz"}'
  end
end
