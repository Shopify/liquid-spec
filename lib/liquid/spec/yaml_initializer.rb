# frozen_string_literal: true

# Simple html_safe implementation if ActiveSupport is not available
class SafeString < String
  def html_safe?
    true
  end

  def html_safe
    self
  end

  def to_s
    self
  end
end

unless defined?(ActiveSupport::SafeBuffer)
  class String
    def html_safe
      SafeString.new(self)
    end
  end
end

# ShopifyFileSystem for specs that need a file system
class ShopifyFileSystem
  attr_reader :data

  def initialize(data)
    data ||= {}
    @data = data.transform_keys do |key|
      next key if key == "instantiate"

      key = key.to_s.downcase
      key = "#{key}.liquid" unless key.end_with?(".liquid")
      key
    end
    @data.delete("instantiate")
  end

  def read_template_file(template_path)
    template_path = template_path.to_s
    template_path = "#{template_path}.liquid" unless template_path.downcase.end_with?(".liquid")
    data.find { |name, _| name.casecmp?(template_path) }&.last || begin
      full_name = "snippets/#{template_path}"
      raise Liquid::FileSystemError, "Could not find asset #{full_name}"
    end
  end

  def to_h
    @data.transform_keys(&:to_s)
  end

  def presence
    return if @data.empty?

    self
  end
end

# BlankFileSystem - always raises file not found
class BlankFileSystem
  def initialize(_data = nil)
  end

  def read_template_file(template_path)
    raise Liquid::FileSystemError, "This liquid context does not allow includes."
  end
end

# ContextWithRaisingSubcontext is defined lazily in test_drops.rb
# since it needs Liquid::Context to be loaded first
