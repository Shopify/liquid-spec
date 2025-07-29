# frozen_string_literal: true

require "cgi"

module TestDrops
  module DropActsAsString
    include Comparable

    alias_method :eql?, :==

    def to_str
      to_s
    end

    def <=>(other)
      to_s <=> other
    end

    def include?(right)
      right = right.to_s if right.respond_to?(:to_s)
      to_s.include?(right)
    end

    def match(other)
      to_s.match(other)
    end

    def match?(other)
      to_s.match?(other)
    end

    def split(pattern)
      to_s.split(pattern)
    end

    def size
      to_s.size
    end

    def empty?
      s = to_s
      !s || s.empty?
    end

    def json_filter
      to_s
    end

    def hash
      to_s.hash
    end

    def to_liquid_hashable
      to_s
    end
  end

  class FakeDrop < Liquid::Drop
    module Mixin
      def inspect
        Object.instance_method(:inspect).bind_call(self)
      end
    end

    include Mixin
  end

  class Money
    def to_liquid
      100
    end
  end

  class FakeMoney
    def to_liquid
      "100"
    end

    def to_s
      "500"
    end
  end

  module Metafields
    class StringDrop < FakeDrop
      include(DropActsAsString)

      def initialize(value)
        super()
        @value = value
      end

      def to_liquid_value
        @value
      end

      def to_s
        @value
      end

      def inspect
        "#<#{self.class} @value=#{@value.inspect}>" # for debugging
      end

      def hash
        to_s.hash
      end

      def <=>(other)
        to_s <=> other
      end
    end

    class FakeArticleDrop < FakeDrop
      include(DropActsAsString)

      def initialize(value)
        super()
        @value = value
      end

      def to_s
        @value
      end
    end

    class IntDrop < FakeDrop
      include(Comparable)

      def initialize(value)
        super()
        @value = value
      end

      def to_liquid_value
        @value
      end

      def <=>(other)
        @value <=> other
      end

      def to_i
        @value
      end

      def to_s
        @value.to_s
      end
    end

    class MetaComparableDrop < FakeDrop
      include(Comparable)

      def initialize(inner)
        super()
        @inner = inner
      end

      def to_liquid_value
        @inner
      end

      def <=>(other)
        @inner <=> other
      end
    end

    class BooleanDrop < FakeDrop
      def initialize(value)
        super()
        @value = value
      end

      def to_liquid_value
        @value
      end

      def to_s
        @value.to_s
      end
    end
  end

  module LiquidHelper
    module FakeDrops
      class NotStandardError < NotImplementedError; end
      class TestError < StandardError; end
      class ToLiquidError < StandardError; end
      class NotRaisedError < NotImplementedError; end
      class LiquidError < Liquid::Error; end

      class SafeStringDrop < FakeDrop
        def to_s
          "&gt;".html_safe
        end
      end

      class NotSafeStringDrop < FakeDrop
        def to_s
          safebuffer = ActiveSupport::SafeBuffer.new(">")
          safebuffer.instance_variable_set(:@html_safe, false)
          safebuffer
        end
      end

      class RaisingToSDrop < FakeDrop
        def to_s
          raise "test this"
        end
      end

      class DropWithSize < FakeDrop
        def [](key)
          "from_standard_lookup" if key == "size"
        end

        def size
          "from_method"
        end
      end

      class DropWithLiquidSize < FakeDrop
        def size
          ObjectWithToLiquid.new("to_liquid value")
        end
      end

      class ContextAwareDrop < FakeDrop
        def initialize(id:)
          @id = id
          super()
        end

        def to_s
          @id.to_s
        end

        attr_reader :id

        def context_id = @context.object_id
      end

      class RatingDrop < FakeDrop
        def initialize(rating, min, max)
          super()
          @rating = rating
          @min = min
          @max = max
        end

        attr_reader :rating, :min, :max
      end

      class IterDrop
        include(Enumerable)

        def each
          raise "to_a should not be called"
        end
      end

      class AnyDrop < FakeDrop
        attr_reader :value

        def initialize(value)
          super()
          @value = value
        end

        def to_liquid_value
          @value
        end
      end

      class ComparableDrop < FakeDrop
        include Comparable

        def initialize(value)
          super()
          @value = value
        end

        def <=>(other)
          @value <=> other
        end
      end

      class MuffinDrop < FakeDrop
        def initialize(count: 1, flavor:)
          @count = count
          @flavor = flavor
          super()
        end

        attr_reader :count

        attr_reader :flavor
      end

      class MuffinCollectionDrop < FakeDrop
        attr_reader :context

        def initialize(muffin_count = 10)
          super()
          @muffins = muffin_count.times.map { |i| MuffinDrop.new(flavor: "blueberry-#{i}", count: i) }
        end

        def title
          "Muffins"
        end

        def muffins_count
          muffins.count
        end

        def muffins
          if (paginator = @context&.find_variable("paginate"))
            return @muffins.first(paginator.page_size)
          end

          @muffins
        end
      end

      class CollectionMuffins < FakeDrop
        def initialize(collection, context = nil)
          super()
          @collection = collection
          @context = context
        end

        def to_liquid
          @collection.context = @context
          @collection.muffins
        end
      end

      class RaisingDrop < FakeDrop
        def initialize(raise_to_liquid: false)
          super()
          @raise_to_liquid = raise_to_liquid
        end

        def internal_error
          raise TestError, "Error"
        end

        def not_standard_error
          raise NotStandardError, "Not a StandardError"
        end

        def timeout_error
          raise Timeout::Error, "Timeout"
        end

        def liquid_error
          raise LiquidError, "liquid"
        end

        def zero_division_error
          1 / 0
        end

        def to_liquid
          raise ToLiquidError, "to_liquid error" if @raise_to_liquid

          self
        end
      end

      class BlankSupportDrop < FakeDrop
        def initialize(blank)
          @blank = blank
          super()
        end

        def blank?
          @blank
        end
      end

      class DropWithContext < FakeDrop
        attr_reader :context, :context_history

        def initialize
          @context_history = []
          super
        end

        def dup
          self.class.new
        end

        def context=(context)
          @context_history << context unless context_history.last.object_id == context.object_id
          super
        end

        def context_history_length
          @context_history.length
        end
      end

      class ObjectWithToLiquid < Struct.new(:to_liquid)
      end

      class DropToString < FakeDrop
        def initialize(string)
          @string = string
          super()
        end

        def to_s
          @string
        end
      end

      class PaginatedDrop < FakeDrop
        attr_reader :count

        def initialize(method, count = 0)
          @method = method
          @count = count
          super()
        end

        def paginate_key
          "key"
        end

        def each(&block)
          identifier = @context.registers.static[:paginated_liquid_variable]
          return "ERROR" unless identifier
          return "ERROR" if identifier.source_drop != self
          return "ERROR" if identifier.method_name != @method

          paginator = @context.find_variable("paginate")
          return "ERROR" unless paginator

          page_size = paginator.page_size
          current_offset = paginator.current_offset

          (current_offset..(current_offset + page_size - 1)).each(&block)
        end
      end

      class OnceProductsDrop < FakeDrop
        def count
          raise "already called" if @already_called

          @already_called = true
          10
        end

        def each(&block)
          (1..10).each(&block)
        end
      end

      class OnceCollectionDrop < FakeDrop
        def products
          @products ||= OnceProductsDrop.new
        end
      end

      class CollectionDrop < FakeDrop
        def products
          @products ||= PaginatedDrop.new(:products, 10)
        end
      end

      class DropWithChangingContext < FakeDrop
        def context_id
          @context.object_id
        end

        def change_context
          @context = Liquid::Context.new
          "test"
        end
      end

      class EnumerableDrop < Liquid::Drop
        include Enumerable

        def each(&block)
          ["a", "b", "c"].each(&block)
        end

        def last
          "c"
        end

        def [](key)
          key
        end
      end

      class FakeBlockDrop < Liquid::Drop
        def initialize(type)
          @type = type
          super()
        end

        def json_filter
          { type: @type }
        end

        attr_reader :type
      end

      class CountryDrop < FakeDrop
        attr_reader :iso_code, :currency

        def initialize(iso_code, input_name, currency_iso_code = nil, currency_symbol = nil)
          super()
          @iso_code = iso_code
          @input_name = input_name
          @currency = CurrencyDrop.new(currency_iso_code, currency_symbol)
        end

        def name
          return @name if defined?(@name)

          @name = CGI.escapeHTML(@input_name).html_safe
        end
      end

      class CurrencyDrop < FakeDrop
        attr_reader :iso_code, :symbol

        def initialize(iso_code, symbol)
          super()
          @iso_code = iso_code
          @symbol = symbol
        end
      end

      class LocalizationDrop < FakeDrop
        attr_reader :country, :available_countries

        def initialize(country:, available_countries:)
          @country = country
          @available_countries = available_countries
          super()
        end
      end

      class FiberDrop < FakeDrop
        def initialize(value)
          @lazy_value = value
          super()
        end

        def fiber_lookup
          Fiber.new do
            Fiber.yield(begin
              Fiber.new do
                value = @context[@lazy_value]
                Fiber.yield value
              end.resume
            end)
          end.resume
        end

        def fiber_value
          Fiber.new do
            Fiber.yield(begin
              Fiber.new do
                value = @lazy_value.dup
                Fiber.yield value
              end.resume
            end)
          end.resume
        end
      end

      class MediaDrop < FakeDrop
        def initialize(media_type: "video", position: 1, aspect_ratio: 1.5)
          @media_type = media_type
          @position = position
          @aspect_ratio = aspect_ratio
          super()
        end

        attr_reader :media_type, :position, :aspect_ratio

        def id
          # Always allocate a new string using CGI.escape_html
          CGI.escapeHTML("media_#{@position}_#{Time.now.to_i}")
        end

        def preview_image
          {
            "src" => "//example.com/preview.jpg",
          }
        end
      end
    end
  end

  class HtmlSafeHash < Hash
    HTML_ESCAPE_TABLE = {
      ">" => "&gt;",
      "<" => "&lt;",
      '"' => "&quot;",
    }.freeze

    def to_s
      Liquid::Utils.hash_inspect(self).gsub(/[<>"]/, HTML_ESCAPE_TABLE)
    end
  end

  class CollationAwareHash < Hash
    def []=(key, value)
      super(collate_key(key), value)
    end

    def [](key)
      super(collate_key(key))
    end

    def key?(key)
      super(collate_key(key))
    end

    private

    def collate_key(key)
      return key unless key.is_a?(String)
      return collated_keys[key] if collated_keys.key?(key)

      collated = string_utils_to_utf8mb4(key).freeze
      collated_keys[key] = collated
    end

    def collated_keys
      @collated_keys ||= {}
    end

    def string_utils_to_utf8mb4(input)
      result = input.to_s.dup
      result.sub!(/ *\z/, "") if result[-1] == " "
      result.downcase!
      result
    end
  end
end
