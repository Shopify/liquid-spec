# frozen_string_literal: true

# typed: true

module StringUtils
  extend self

  UNICODE_REGEX = /[^\x00-\x7F]/
  EMOJI_REGEX = '\u{00A9}\u{00AE}\u{203C}\u{2049}\u{2122}\u{2139}\u{2194}-\u{2199}\u{21A9}-\u{21AA}\u{231A}-\u{231B}\u{2328}\u{23CF}\u{23E9}-\u{23F3}\u{23F8}-\u{23FA}\u{24C2}\u{25AA}-\u{25AB}\u{25B6}\u{25C0}\u{25FB}-\u{25FE}\u{2600}-\u{2604}\u{260E}\u{2611}\u{2614}-\u{2615}\u{2618}\u{261D}\u{2620}\u{2622}-\u{2623}\u{2626}\u{262A}\u{262E}-\u{262F}\u{2638}-\u{263A}\u{2648}-\u{2653}\u{2660}\u{2663}\u{2665}-\u{2666}\u{2668}\u{267B}\u{267F}\u{2692}-\u{2694}\u{2696}-\u{2697}\u{2699}\u{269B}-\u{269C}\u{26A0}-\u{26A1}\u{26AA}-\u{26AB}\u{26B0}-\u{26B1}\u{26BD}-\u{26BE}\u{26C4}-\u{26C5}\u{26C8}\u{26CE}-\u{26CF}\u{26D1}\u{26D3}-\u{26D4}\u{26E9}-\u{26EA}\u{26F0}-\u{26F5}\u{26F7}-\u{26FA}\u{26FD}\u{2702}\u{2705}\u{2708}-\u{270D}\u{270F}\u{2712}\u{2714}\u{2716}\u{271D}\u{2721}\u{2728}\u{2733}-\u{2734}\u{2744}\u{2747}\u{274C}\u{274E}\u{2753}-\u{2755}\u{2757}\u{2763}-\u{2764}\u{2795}-\u{2797}\u{27A1}\u{27B0}\u{27BF}\u{2934}-\u{2935}\u{2B05}-\u{2B07}\u{2B1B}-\u{2B1C}\u{2B50}\u{2B55}\u{3030}\u{303D}\u{3297}\u{3299}\u{1F004}\u{1F0CF}\u{1F170}-\u{1F171}\u{1F17E}-\u{1F17F}\u{1F18E}\u{1F191}-\u{1F19A}\u{1F201}-\u{1F202}\u{1F21A}\u{1F22F}\u{1F232}-\u{1F23A}\u{1F250}-\u{1F251}\u{1F300}-\u{1F321}\u{1F324}-\u{1F393}\u{1F396}-\u{1F397}\u{1F399}-\u{1F39B}\u{1F39E}-\u{1F3F0}\u{1F3F3}-\u{1F3F5}\u{1F3F7}-\u{1F4FD}\u{1F4FF}-\u{1F53D}\u{1F549}-\u{1F54E}\u{1F550}-\u{1F567}\u{1F56F}-\u{1F570}\u{1F573}-\u{1F579}\u{1F587}\u{1F58A}-\u{1F58D}\u{1F590}\u{1F595}-\u{1F596}\u{1F5A5}\u{1F5A8}\u{1F5B1}-\u{1F5B2}\u{1F5BC}\u{1F5C2}-\u{1F5C4}\u{1F5D1}-\u{1F5D3}\u{1F5DC}-\u{1F5DE}\u{1F5E1}\u{1F5E3}\u{1F5EF}\u{1F5F3}\u{1F5FA}-\u{1F64F}\u{1F680}-\u{1F6C5}\u{1F6CB}-\u{1F6D0}\u{1F6E0}-\u{1F6E5}\u{1F6E9}\u{1F6EB}-\u{1F6EC}\u{1F6F0}\u{1F6F3}\u{1F910}-\u{1F918}\u{1F980}-\u{1F984}\u{1F9C0}'
  WORDS_REGEX = '\p{Word}'
  UTF8_REGEX = /[^[#{WORDS_REGEX}#{EMOJI_REGEX}]]+/u
  APPROXIMATIONS = {
    "Þ" => "Th",
    "ß" => "ss",
    "à" => "a",
    "á" => "a",
    "â" => "a",
    "ã" => "a",
    "ä" => "a",
    "å" => "a",
    "æ" => "ae",
    "ç" => "c",
    "è" => "e",
    "é" => "e",
    "ê" => "e",
    "ë" => "e",
    "ì" => "i",
    "í" => "i",
    "î" => "i",
    "ï" => "i",
    "ð" => "d",
    "ñ" => "n",
    "ò" => "o",
    "ó" => "o",
    "ô" => "o",
    "õ" => "o",
    "ö" => "o",
    "ø" => "o",
    "ù" => "u",
    "ú" => "u",
    "û" => "u",
    "ü" => "u",
    "ý" => "y",
    "þ" => "th",
    "ÿ" => "y",
    "ā" => "a",
    "ă" => "a",
    "ą" => "a",
    "ć" => "c",
    "ĉ" => "c",
    "ċ" => "c",
    "č" => "c",
    "ď" => "d",
    "đ" => "d",
    "ē" => "e",
    "ĕ" => "e",
    "ė" => "e",
    "ę" => "e",
    "ě" => "e",
    "ĝ" => "g",
    "ğ" => "g",
    "ġ" => "g",
    "ģ" => "g",
    "ĥ" => "h",
    "ħ" => "h",
    "ĩ" => "i",
    "ī" => "i",
    "ĭ" => "i",
    "į" => "i",
    "ı" => "i",
    "ĳ" => "ij",
    "ĵ" => "j",
    "ķ" => "k",
    "ĸ" => "k",
    "ĺ" => "l",
    "ļ" => "l",
    "ľ" => "l",
    "ŀ" => "l",
    "ł" => "l",
    "ń" => "n",
    "ņ" => "n",
    "ň" => "n",
    "ŉ" => "'n",
    "ŋ" => "ng",
    "ō" => "o",
    "ŏ" => "o",
    "ő" => "o",
    "œ" => "oe",
    "ŕ" => "r",
    "ŗ" => "r",
    "ř" => "r",
    "ś" => "s",
    "ŝ" => "s",
    "ş" => "s",
    "š" => "s",
    "ţ" => "t",
    "ť" => "t",
    "ŧ" => "t",
    "ũ" => "u",
    "ū" => "u",
    "ŭ" => "u",
    "ů" => "u",
    "ű" => "u",
    "ų" => "u",
    "ŵ" => "w",
    "ŷ" => "y",
    "ź" => "z",
    "ż" => "z",
    "ž" => "z",
  }.freeze

  HybridTransliterator = ->(string) {
    string.gsub(UNICODE_REGEX) do |char|
      APPROXIMATIONS[char] || char
    end
  }

  def to_utf8_handle(input)
    result = ActiveSupport::Multibyte::Unicode.tidy_bytes(input.to_s.downcase)
    result = result.unicode_normalize(:nfc)
    result = HybridTransliterator.call(result).downcase if UNICODE_REGEX.match(result)
    result.delete!("'\"()[]")
    result.gsub!(UTF8_REGEX, "-")
    result.gsub!(/\A-+|-+\z/, "")
    result.to_s
  end
end

module LiquidHelper
  module FakeFilters
    def ruby_default(text, default)
      text || default
    end

    def fake_ruby_error_filter(text)
      raise StandardError, "fake ruby error"
    end

    def sleepy(ms)
      sleep(seconds.to_i / 1000.0)
    end

    def append(text, tail)
      Liquid::Utils.to_s(text) + Liquid::Utils.to_s(tail)
    end

    # options is a hash that accepts these keys:
    # - case, which can be "upcase" or "downcase"
    def modify_case(text, options)
      if options["case"] == "upcase"
        Liquid::Utils.to_s(text).upcase
      elsif options["case"] == "downcase"
        Liquid::Utils.to_s(text).downcase
      end
    end

    def fakey(text, arg = nil)
      Liquid::Utils.to_s(text) + " (fake)"
    end

    def raisy(text)
      raise "Error"
    end

    def html_safe_in_ruby?(text)
      text.html_safe?
    end

    def args_to_s(text, options)
      text = Liquid::Utils.to_s(text)
      output = "primary: #{text}\n"
      options.each do |key, value|
        output << "#{key.inspect} => #{value.inspect}, "
      end
      output
    end

    def asset_url(name)
      "ruby asset_url for #{name}"
    end

    def read_current_tags(name)
      @context.find_variable("current_tags")
    end

    def read_template(name)
      @context.find_variable("template")
    end

    def image_url(url, *args)
      transforms = args.first
      query_params = transforms.map { |key, value| "#{key}=#{value}" }
      "#{url}?#{query_params.join("&")}"
    end

    def product_img_url(input, arg1 = nil, arg2 = nil)
      url = input["url"]
      "#{url}?arg1=#{arg1}&arg2=#{arg2}"
    end

    def handleize(input)
      StringUtils.to_utf8_handle(Liquid::Utils.to_s(input))
    end

    def dup(input)
      input.dup
    end

    def translate(key, options = {})
      _section_drop = @context.find_variable("section")
      _block_drop = @context.find_variable("block")
      slug = options.map { |k, v| "#{Liquid::Utils.to_s(k)}-#{Liquid::Utils.to_s(v)}" }.join("-")
      "translated-#{Liquid::Utils.to_s(key)}-#{slug}"
    end
    alias_method :t, :translate

    # Realistic model_viewer_tag filter that accepts drop and options hash
    def model_viewer_tag(drop, options = {})
      options = {} unless options.is_a?(Hash)

      # Process all the options like the real filter does
      image_size = options.delete("image_size") || "master"
      data_model_id = options["data-model-id"]

      # Build a simple model viewer tag
      attrs = []
      attrs << "src=\"//example.com/model.glb\""
      attrs << "poster=\"//example.com/preview.jpg?size=#{image_size}\""
      attrs << "data-model-id=\"#{data_model_id}\"" if data_model_id

      options.each do |key, value|
        next if key == "image_size"

        attrs << "#{key}=\"#{value}\""
      end

      "<model-viewer #{attrs.join(" ")}></model-viewer>"
    end

    # Another filter with many arguments for testing
    def video_tag(media, options = {})
      options = {} unless options.is_a?(Hash)

      # Process options
      attrs = []
      attrs << "src=\"//example.com/video.mp4\""

      options.each do |key, value|
        attrs << "#{key}=\"#{value}\""
      end

      "<video #{attrs.join(" ")}></video>"
    end
  end

  module JsonFilter
    def json(input)
      if input.is_a?(BigDecimal)
        input.to_s
      else
        item_as_json(input).to_json
      end
    end

    private

    def item_as_json(item)
      if item.respond_to?(:call)
        item = item.call(@context)
      end

      if item.respond_to?(:to_liquid)
        item = item.to_liquid
      end

      if item.respond_to?(:context=)
        item.context = @context
      end

      if item.respond_to?(:json_filter)
        item_as_json(item.json_filter)
      elsif item.is_a?(Hash)
        item.each_with_object({}) { |(key, value), hash| hash[key] = item_as_json(value) }
      elsif item&.respond_to?(:to_a)
        item.to_a.map { |value| item_as_json(value) }
      elsif item.is_a?(Liquid::Drop)
        { error: "json not allowed for this object" }
      else
        item
      end
    end
  end

  Liquid::Environment.default.register_filter(FakeFilters)
  Liquid::Environment.default.register_filter(JsonFilter)
end
