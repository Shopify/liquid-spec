class TestThing
  attr_reader :foo

  def initialize
    @foo = 0
  end

  def to_s
    "woot: #{@foo}"
  end

  def [](_whatever)
    to_s
  end

  def to_liquid
    @foo += 1
    self
  end
end

class TestEnumerable < Liquid::Drop
  include Enumerable

  def each(&block)
    [{ "foo" => 1, "bar" => 2 }, { "foo" => 2, "bar" => 1 }, { "foo" => 3, "bar" => 3 }].each(&block)
  end
end

class NumberLikeThing < Liquid::Drop
  def initialize(amount)
    @amount = amount
  end

  def to_number
    @amount
  end
end


class ThingWithToLiquid
  def to_liquid
    'foobar'
  end
end

class ForTagTest
  class LoaderDrop < Liquid::Drop
    attr_accessor :each_called, :load_slice_called

    def initialize(data)
      @data = data
    end

    def each
      @each_called = true
      @data.each { |el| yield el }
    end

    def load_slice(from, to)
      @load_slice_called = true
      @data[(from..to - 1)]
    end
  end
end

class TableRowTest
  class ArrayDrop < Liquid::Drop
    include Enumerable

    def initialize(array)
      @array = array
    end

    def each(&block)
      @array.each(&block)
    end
  end
end

class IntegerDrop < Liquid::Drop
  def initialize(value)
    super()
    @value = value.to_i
  end

  def ==(other)
    @value == other
  end

  def to_s
    @value.to_s
  end

  def to_liquid_value
    @value
  end
end

class ThingWithValue < Liquid::Drop
  def value
    3
  end
end

class BooleanDrop < Liquid::Drop
  def initialize(value)
    super()
    @value = value
  end

  def ==(other)
    @value == other
  end

  def to_liquid_value
    @value
  end

  def to_s
    @value ? "Yay" : "Nay"
  end
end

class BlankTestFileSystem
  def read_template_file(template_path)
    template_path
  end
end

class ProfilerTest < Minitest::Test
  class ProfilingFileSystem
    def read_template_file(template_path)
      "Rendering template {% assign template_name = '#{template_path}'%}\n{{ template_name }}"
    end
  end
end

class StubFileSystem
  attr_reader :file_read_count

  def initialize(values)
    @file_read_count = 0
    @values          = values
  end

  def read_template_file(template_path)
    @file_read_count += 1
    @values.fetch(template_path)
  end
end

class TestFileSystem
  def read_template_file(template_path)
    case template_path
    when "product"
      "Product: {{ product.title }} "

    when "product_alias"
      "Product: {{ product.title }} "

    when "locale_variables"
      "Locale: {{echo1}} {{echo2}}"

    when "variant"
      "Variant: {{ variant.title }}"

    when "nested_template"
      "{% include 'header' %} {% include 'body' %} {% include 'footer' %}"

    when "body"
      "body {% include 'body_detail' %}"

    when "nested_product_template"
      "Product: {{ nested_product_template.title }} {%include 'details'%} "

    when "recursively_nested_template"
      "-{% include 'recursively_nested_template' %}"

    when "pick_a_source"
      "from TestFileSystem"

    when 'assignments'
      "{% assign foo = 'bar' %}"

    when 'break'
      "{% break %}"

    else
      template_path
    end
  end
end
