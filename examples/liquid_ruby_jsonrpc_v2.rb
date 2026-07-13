#!/usr/bin/env ruby
# frozen_string_literal: true

# Reference adapter for the Rust liquid-spec runner. This is intentionally an
# external JSON-RPC process: the Rust binary never links Liquid or embeds a
# second implementation for comparison.

require "base64"
require "json"
require "time"
require "liquid"

class LiquidSpecRubyV2
  def initialize
    @templates = {}
    @next_id = 0
  end

  def run
    $stdout.sync = true
    $stdin.each_line do |line|
      request = JSON.parse(line)
      response = dispatch(request)
      puts JSON.generate(response) if response
    rescue JSON::ParserError
      puts JSON.generate(error_response(nil, -32700, "Parse error"))
    end
  end

  private

  def dispatch(request)
    return nil if request["method"] == "shutdown" && !request.key?("id")

    id = request["id"]
    params = request["params"] || {}
    # JSON-RPC invalid-parameter failures are transport errors. Liquid parse
    # and render failures below remain typed successful outcomes.
    if id && !params.is_a?(Hash)
      return error_response(id, -32602, "params must be an object")
    end
    case request["method"]
    when "template.compile"
      bundle = params["bundle"]
      unless bundle.is_a?(Hash) && bundle["entry"].is_a?(String) && bundle["sources"].is_a?(Hash)
        return error_response(id, -32602, "compile requires bundle.entry and bundle.sources")
      end
    when "template.render"
      unless params["template_id"].is_a?(String)
        return error_response(id, -32602, "render requires template_id")
      end
      unless @templates.key?(params["template_id"])
        return error_response(id, -32602, "unknown template_id")
      end
    when "template.release"
      unless params["template_id"].is_a?(String) && @templates.key?(params["template_id"])
        return error_response(id, -32602, "unknown template_id")
      end
    end
    result = case request["method"]
    when "initialize"
      {
        "protocol_version" => "2",
        "implementation" => { "name" => "liquid-ruby", "version" => Liquid::VERSION, "language" => "ruby" },
        "capabilities" => {
          "parse_modes" => %w[strict strict2 lax],
          "render_error_modes" => %w[raise inline],
          "features" => %w[core drops ruby_compat inline_errors],
          "fixture_sets" => { "standard-drops" => 1 },
          "artifacts" => false,
          "benchmark" => true,
        },
      }
    when "protocol.echo"
      params
    when "template.compile"
      compile(params)
    when "template.render"
      render(params)
    when "template.release"
      release(params)
    when "benchmark.run"
      benchmark(params)
    else
      return error_response(id, -32601, "Method not found")
    end
    success_response(id, result)
  rescue Liquid::SyntaxError => e
    success_response(id, { "error" => liquid_error("parse", e) })
  rescue StandardError => e
    success_response(id, { "error" => liquid_error("render", e) })
  end

  def compile(params)
    bundle = params.fetch("bundle")
    options = params.fetch("options", {})
    parse_options = { line_numbers: !!options["line_numbers"] }
    parse_options[:error_mode] = options["parse_mode"].to_sym if options["parse_mode"]
    templates = {}
    deferred = {}
    bundle.fetch("sources").each do |name, source|
      begin
        templates[name] = Liquid::Template.parse(source, **parse_options)
      rescue Liquid::SyntaxError => e
        deferred[name] = e
      end
    end
    entry = bundle.fetch("entry")
    raise deferred[entry] if deferred.key?(entry)
    id = "template_#{@next_id += 1}"
    @templates[id] = { entry: entry, templates: templates, deferred: deferred, files: bundle.fetch("sources") }
    { "ok" => { "template_id" => id } }
  end

  def render(params)
    state = @templates.fetch(params.fetch("template_id"))
    environment = decode(params.fetch("environment", {}))
    options = params.fetch("options", {})
    registers = { file_system: HashFileSystem.new(state[:files], state[:templates], state[:deferred]) }
    # `now` is the protocol-level render clock. Keep it in the host-owned
    # registers (so templates cannot resolve it as an assign), and freeze
    # Ruby's wall clock for the duration of this render so Liquid's built-in
    # date filter observes the same deterministic instant.
    current_time = options["now"] && Time.iso8601(options["now"])
    registers[:current_time] = current_time if current_time
    context = Liquid::Context.build(
      static_environments: environment,
      registers: Liquid::Registers.new(registers),
      rethrow_errors: options.fetch("error_policy", "raise") != "inline",
    )
    output = if current_time
      with_frozen_time(current_time) { state[:templates].fetch(state[:entry]).render(context) }
    else
      state[:templates].fetch(state[:entry]).render(context)
    end
    { "ok" => { "output" => output, "diagnostics" => [] } }
  end

  # Liquid's date filter resolves the special `now` value through Time.now.
  # Keep the override scoped to one request so concurrent/future renders do
  # not leak a previous spec's deterministic clock into unrelated work.
  def with_frozen_time(time)
    original_now = Time.method(:now)
    Time.define_singleton_method(:now) { time }
    yield
  ensure
    Time.define_singleton_method(:now, original_now) if original_now
  end

  def release(params)
    id = params.fetch("template_id")
    raise ArgumentError, "unknown template_id" unless @templates.delete(id)
    { "ok" => {} }
  end

  def benchmark(params)
    operation = params.fetch("operation")
    iterations = Integer(params.fetch("iterations", 1))
    raise ArgumentError, "iterations must be positive" if iterations <= 0
    batches = []
    digest = nil
    artifact = nil
    iterations.times do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      case operation
      when "compile"
        compile_params = params.merge("options" => params.fetch("compile_options", {}))
        result = compile(compile_params)
        digest = params.dig("bundle", "sources", params.dig("bundle", "entry"))
        artifact = params.dig("bundle", "sources", params.dig("bundle", "entry"))
      when "render"
        result = render(params.merge("options" => params.fetch("render_options", {})))
        digest = result.dig("ok", "output")
      when "artifact_load"
        digest = params["artifact"]
      else
        raise ArgumentError, "unknown benchmark operation"
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started
      batches << { "iterations" => 1, "elapsed_ns" => elapsed }
    end
    result = { "version" => "1", "operation" => operation, "iterations" => iterations, "batches" => batches, "digest" => digest }
    result["artifact"] = artifact if artifact
    { "version" => "1", "operation" => operation, "iterations" => iterations, "batches" => batches, "digest" => digest, "artifact" => artifact }.compact
  end

  def decode(value)
    case value
    when Hash
      tagged = value["$liquid-spec"]
      if tagged
        case tagged["type"]
        when "bytes" then Base64.strict_decode64(tagged.fetch("base64"))
        when "symbol" then tagged.fetch("value").to_sym
        when "integer" then Integer(tagged.fetch("value"))
        when "float"
          case tagged.fetch("value").to_s
          when "nan" then Float::NAN
          when "positive_infinity" then Float::INFINITY
          when "negative_infinity" then -Float::INFINITY
          else Float(tagged.fetch("value"))
          end
        when "date", "time", "datetime" then tagged.fetch("value")
        when "range"
          Range.new(decode(tagged.fetch("start")), decode(tagged.fetch("end")), tagged.fetch("exclusive", false))
        when "map"
          tagged.fetch("entries").to_h { |entry| [decode(entry.fetch("key")), decode(entry.fetch("value"))] }
        when "fixture" then fixture(tagged.fetch("name"), decode(tagged.fetch("params", {})))
        when "object" then decode(tagged.fetch("value"))
        else raise ArgumentError, "unknown typed value #{tagged["type"].inspect}"
        end
      else
        value.transform_values { |child| decode(child) }
      end
    when Array then value.map { |child| decode(child) }
    else value
    end
  end

  def fixture(name, params)
    case name
    when "BooleanDrop" then StandardBooleanDrop.new(params.fetch("value", false))
    when "NumberDrop", "IntegerDrop" then StandardNumberDrop.new(params.fetch("value", 0))
    when "StringDrop" then StandardStringDrop.new(params.fetch("value", ""))
    when "MethodDrop" then StandardMethodDrop.new
    when "IndexDrop" then StandardIndexDrop.new
    when "SequenceDrop" then StandardSequenceDrop.new
    when "NilDrop" then StandardNilDrop.new
    when "OpaqueDrop" then StandardOpaqueDrop.new
    when "ErrorDrop" then StandardErrorDrop.new
    when "NestedDrop" then StandardNestedDrop.new(params)
    else raise ArgumentError, "Ruby reference fixture #{name} is not registered"
    end
  end

  def liquid_error(phase, exception)
    { "phase" => phase, "code" => exception.class.name, "message" => exception.message, "causes" => [] }
  end

  def success_response(id, result) = { "jsonrpc" => "2.0", "id" => id, "result" => result }
  def error_response(id, code, message) = { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message } }

  class HashFileSystem
    def initialize(files, templates, deferred)
      @files = files
      @templates = templates
      @deferred = deferred
    end
    def read_template_file(path)
      name = path.to_s.sub(/\.liquid\z/, "")
      raise @deferred[name] if @deferred.key?(name)
      raise Liquid::FileSystemError, "Could not find template '#{path}'" unless @files.key?(path) || @files.key?(name)
      @files[path] || @files[name]
    end
  end

  class StandardBooleanDrop < Liquid::Drop
    def initialize(value) = @value = value
    def to_liquid_value = @value
    def to_s = @value.to_s
  end
  class StandardNumberDrop < Liquid::Drop
    def initialize(value) = @value = value
    def to_liquid_value = @value
    def to_number = @value
    def to_s = @value.to_s
  end
  class StandardStringDrop < Liquid::Drop
    def initialize(value) = @value = value
    def to_liquid_value = @value
    def to_s = @value.to_s
  end
  class StandardMethodDrop < Liquid::Drop
    def liquid_method_missing(name)
      operation, number = name.to_s.split("_", 2)
      number = Integer(number)
      return number.to_s if operation == "echo"
      return (number * number).to_s if operation == "square"
      return (number * 2).to_s if operation == "double"
      nil
    end
  end
  class StandardIndexDrop < Liquid::Drop
    def [](key) = key.is_a?(Integer) ? %w[zero one two][key] : key.to_s
  end
  class StandardSequenceDrop < Liquid::Drop
    def to_a = %w[first second third]
    def [](key) = { "size" => 3, "first" => "first", "last" => "third" }[key.to_s]
  end
  class StandardNilDrop < Liquid::Drop
    def to_liquid_value = nil
  end
  class StandardOpaqueDrop < Liquid::Drop
    def to_s = "opaque"
  end
  class StandardErrorDrop < Liquid::Drop
    def liquid_method_missing(*) = raise "standard ErrorDrop access"
  end
  class StandardNestedDrop < Liquid::Drop
    def initialize(params) = @params = params
    def [](key) = @params[key.to_s]
  end
end

LiquidSpecRubyV2.new.run if __FILE__ == $PROGRAM_NAME
