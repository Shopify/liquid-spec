require 'minitest/autorun'
require 'liquid'
require 'json'

class LiquidRubyTest < MiniTest::Test
  def assert_liquid_spec(folder_path)
    Liquid::Template.file_system = Liquid::LocalFileSystem.new(folder_path)
    template = Liquid::Template.parse(File.read(folder_path + "/template.liquid"))

    environment_file = folder_path + "/environment.json"

    environment = if File.exist?(environment_file)
      JSON.parse(File.read(folder_path + "/environment.json"))
    else
      {}
    end

    output = template.render(environment)
    expected = File.read(folder_path + "/expected.txt")

    assert_equal(expected, output)
  end
end

spec_folders = File.join(File.dirname(__FILE__), '..', 'specs/complex_specs/**')
Dir[spec_folders].each do |folder_path|
  function_name = folder_path.split("/").last

  LiquidRubyTest.class_eval do
    define_method :"test_spec_#{function_name}" do
      assert_liquid_spec(folder_path)
    end
  end
end

json = JSON.parse(File.read('./specs/simple_specs/tests.json'))
json['tests'].each_with_index do |t, i|
  LiquidRubyTest.class_eval do
    define_method :"test_simple_spec_#{i}" do
      template = Liquid::Template.parse(t['template'])
      environment = JSON.parse(t['environment'])
      output = template.render(environment)
      assert_equal(t['expected'], output)
    end
  end
end
