# frozen_string_literal: true

# Simple html_safe implementation if ActiveSupport is not available
unless defined?(ActiveSupport::SafeBuffer)
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

  class String
    def html_safe
      SafeString.new(self)
    end
  end
end

class SerializableProc
  class << self
    def new(og_code, args: [])
      code = "proc do |" + args.join(",") + "|\n" + og_code + "\nend"
      p = eval(code) # rubocop:disable Security/Eval
      p.instance_variable_set(:@og_code, og_code)

      p
    end
  end
end

class Proc
  def encode_with(coder)
    coder.represent_scalar("!serializable_proc", @og_code)
  end

  def _dump(level)
    @og_code
  end
  class << self
    def _load(args)
      SerializableProc.new(args)
    end
  end
end

# Custom deserialization for Proc objects
YAML.add_domain_type("", "serializable_proc") do |_, val|
  SerializableProc.new(val)
end

YAML.add_domain_type("", "stub_exception_renderer") do |_, val|
  StubExceptionRenderer.new(raise_internal_errors: val["raise_internal_errors"])
end

class ShopifyFileSystem
  attr_reader :data

  def initialize(data)
    @data = data.transform_keys do |key|
      key = key.to_s.downcase
      key = "#{key}.liquid" unless key.end_with?(".liquid")
      key
    end
  end

  def read_template_file(template_path)
    template_path = template_path.to_s
    template_path = "#{template_path}.liquid" unless template_path.downcase.end_with?(".liquid")
    data.find { |name, _| name.casecmp?(template_path) }&.last || begin
      full_name = "snippets/#{template_path}"
      raise Liquid::FileSystemError, "Could not find asset #{full_name}"
    end
  end

  def encode_with(coder)
    coder.represent_map("!shopify_file_system", @data)
  end

  def to_h
    @data.transform_keys(&:to_s)
  end

  def presence
    return if @data.empty?

    self
  end
end

YAML.add_domain_type("", "shopify_file_system") do |_, val|
  ShopifyFileSystem.new(val)
end

YAML.add_domain_type("", "blank_file_system") do |_, _|
  Liquid::BlankFileSystem.new
end

YAML.add_domain_type("", "stub_file_system") do |_, data|
  StubFileSystem.new(data)
end

YAML.add_domain_type("", "safe_buffer") do |_, val|
  val.to_s.html_safe
end

class ContextWithRaisingSubcontext < Liquid::Context
  def new_isolated_subcontext(*)
    raise "boom"
  end
end

YAML.add_domain_type("", "context_klass_with_raising_subcontext") do |_, _|
  ContextWithRaisingSubcontext
end

# Encode SafeBuffer if ActiveSupport is loaded
if defined?(ActiveSupport::SafeBuffer)
  module ActiveSupport
    class SafeBuffer
      def encode_with(coder)
        coder.represent_scalar("!safe_buffer", to_s)
      end
    end
  end
end

class StubExceptionRenderer
  def encode_with(coder)
    coder.represent_map("!stub_exception_renderer", { "raise_internal_errors" => @raise_internal_errors })
  end
end

class StubFileSystem
  def encode_with(coder)
    coder.represent_map("!stub_file_system", @values)
  end
end
