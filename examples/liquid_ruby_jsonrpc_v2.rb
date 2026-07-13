#!/usr/bin/env ruby
# frozen_string_literal: true

# liquid-spec reference adapter (JSON-RPC protocol v2)
# =====================================================
#
# This process is the Shopify/liquid reference used by `liquid-spec --compare`
# and a worked example of a complete adapter. Other implementors should be able
# to read it top-to-bottom and map each section onto their own language.
#
# Contract summary (see also: `liquid-spec docs protocol`):
#   - newline-delimited JSON-RPC 2.0 on stdin/stdout
#   - diagnostics only on stderr (never pollute stdout)
#   - no callbacks: environments arrive as typed JSON values / fixtures
#   - compile and render are separate; render never re-parses source
#
# Dependencies are pulled via bundler/inline so a plain `ruby` invocation works
# without a project Gemfile:
#
#   ruby examples/liquid_ruby_jsonrpc_v2.rb

# ── deps ─────────────────────────────────────────────────────────────────────

require "bundler/inline"

# Gem install chatter must not touch stdout (that stream is the RPC wire).
begin
  original_stdout = $stdout
  $stdout = $stderr
  gemfile(true) do
    source "https://rubygems.org"
    gem "base64"
    gem "bigdecimal"
    gem "liquid", "~> 5.13"
    gem "activesupport", require: false # SafeBuffer / html_safe only
  end
ensure
  $stdout = original_stdout if original_stdout
end

require "base64"
require "json"
require "time"
require "liquid"
begin
  require "active_support/core_ext/string/output_safety"
rescue LoadError
  # SafeBuffer fixtures fall back to plain strings without ActiveSupport.
end

# ── server ───────────────────────────────────────────────────────────────────

class LiquidRubyReferenceAdapter
  PROTOCOL_VERSION = "2"

  def initialize
    @templates = {}
    @next_id = 0
  end

  def run
    $stdout.sync = true
    $stdin.each_line do |line|
      message = JSON.parse(line)
      response = handle(message)
      puts(JSON.generate(response)) if response
    rescue JSON::ParserError
      puts(JSON.generate(rpc_error(nil, -32_700, "Parse error")))
    end
  end

  private

  # Dispatch one JSON-RPC message. Notifications (no id) return nil.
  def handle(message)
    method = message["method"]
    id = message["id"]
    params = message["params"] || {}

    return nil if method == "shutdown" && !message.key?("id")
    return rpc_error(id, -32_602, "params must be an object") if id && !params.is_a?(Hash)

    validation_error = validate_request(method, params)
    return rpc_error(id, -32_602, validation_error) if validation_error

    case method
    when "initialize"       then rpc_result(id, initialize_result)
    when "protocol.echo"    then rpc_result(id, params)
    when "template.compile" then rpc_result(id, compile(params))
    when "template.render"  then rpc_result(id, render(params))
    when "template.release" then rpc_result(id, release(params))
    when "benchmark.run"    then rpc_result(id, benchmark(params))
    else
      rpc_error(id, -32_601, "Method not found: #{method}")
    end
  rescue Liquid::SyntaxError => e
    rpc_result(id, { "error" => liquid_error("parse", e) })
  rescue StandardError => e
    # Liquid render failures are still successful JSON-RPC results with a typed
    # error payload. Protocol failures use rpc_error instead.
    rpc_result(id, { "error" => liquid_error("render", e) })
  end

  # Reject malformed request shapes as JSON-RPC invalid-params errors. Once a
  # request has the right shape, Liquid parse/render failures are typed results.
  def validate_request(method, params)
    case method
    when "template.compile"
      bundle = params["bundle"]
      return "compile requires bundle.entry and bundle.sources" unless
        bundle.is_a?(Hash) && bundle["entry"].is_a?(String) && bundle["sources"].is_a?(Hash)
    when "template.render"
      template_id = params["template_id"]
      return "render requires template_id" unless template_id.is_a?(String)
      return "unknown template_id" unless @templates.key?(template_id)
    when "template.release"
      template_id = params["template_id"]
      return "release requires template_id" unless template_id.is_a?(String)
      return "unknown template_id" unless @templates.key?(template_id)
    end
    nil
  end

  def initialize_result
    {
      "protocol_version" => PROTOCOL_VERSION,
      "implementation" => {
        "name" => "liquid-ruby",
        "version" => Liquid::VERSION,
        "language" => "ruby",
      },
      "capabilities" => {
        "parse_modes" => %w[strict2 strict lax],
        "render_error_modes" => %w[raise inline],
        # Positive claims only. The runner skips specs that need more.
        "features" => %w[
          core
          drops
          ruby_compat
          ruby_types
          ruby_drops
          binary_data
          inline_errors
          self_environment_shadowing
          template_factory
        ],
        "fixture_sets" => {
          "standard-drops" => 1,
          "ruby-compat" => 1,
        },
        "artifacts" => false,
        "benchmark" => true,
      },
    }
  end

  # Parse every source in the bundle up front. Partial syntax errors are retained
  # and raised when the partial is actually read (Shopify/liquid behavior).
  def compile(params)
    bundle = require_bundle(params["bundle"])
    options = params["options"] || {}
    parse_options = { line_numbers: !!options["line_numbers"] }
    parse_options[:error_mode] = options["parse_mode"].to_sym if options["parse_mode"]

    templates = {}
    deferred = {}
    bundle["sources"].each do |name, source|
      templates[name] = Liquid::Template.parse(source, **parse_options)
    rescue Liquid::SyntaxError => e
      deferred[name] = e
    end

    entry = bundle["entry"]
    raise deferred[entry] if deferred.key?(entry)

    template_id = "t#{@next_id += 1}"
    @templates[template_id] = {
      entry: entry,
      templates: templates,
      deferred: deferred,
      sources: bundle["sources"],
    }
    { "ok" => { "template_id" => template_id } }
  end

  # Render uses only the compiled handle. Source is never re-parsed here.
  def render(params)
    template_id = params["template_id"]
    raise ArgumentError, "render requires template_id" unless template_id.is_a?(String)

    state = @templates[template_id]
    raise ArgumentError, "unknown template_id" unless state

    environment = decode_value(params["environment"] || {})
    options = params["options"] || {}
    error_policy = options.fetch("error_policy", "raise")

    registers = {
      file_system: BundleFileSystem.new(state[:sources], state[:deferred]),
    }
    # Protocol clock: keep in registers (not assigns) and freeze Time.now for
    # filters such as `date: "%Y"` that consult the host clock.
    now = options["now"] && Time.iso8601(options["now"])
    registers[:current_time] = now if now

    context = build_context(environment, registers, error_policy)
    template = state[:templates].fetch(state[:entry])
    output = if now
      with_frozen_time(now) { template.render(context) }
    else
      template.render(context)
    end

    { "ok" => { "output" => output, "diagnostics" => [] } }
  end

  def build_context(environment, registers, error_policy)
    if Liquid::Context.respond_to?(:build)
      Liquid::Context.build(
        static_environments: environment,
        registers: Liquid::Registers.new(registers),
        rethrow_errors: error_policy != "inline",
      )
    else
      Liquid::Context.new(
        environment,
        {},
        registers,
        error_policy != "inline",
      )
    end
  end

  def release(params)
    template_id = params["template_id"]
    unless template_id.is_a?(String) && @templates.delete(template_id)
      raise ArgumentError, "unknown template_id"
    end

    { "ok" => {} }
  end

  # Server-owned timing. Each iteration measures only the named operation so
  # transport latency stays outside the reported batches.
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
        compile(params.merge("options" => params["compile_options"] || {}))
        digest = params.dig("bundle", "sources", params.dig("bundle", "entry"))
        artifact = digest
      when "render"
        result = render(params.merge("options" => params["render_options"] || {}))
        digest = result.dig("ok", "output")
      when "artifact_load"
        digest = params["artifact"]
      else
        raise ArgumentError, "unknown benchmark operation #{operation.inspect}"
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started
      batches << { "iterations" => 1, "elapsed_ns" => elapsed }
    end

    {
      "version" => "1",
      "operation" => operation,
      "iterations" => iterations,
      "batches" => batches,
      "digest" => digest,
      "artifact" => artifact,
    }.compact
  end

  def require_bundle(bundle)
    unless bundle.is_a?(Hash) && bundle["entry"].is_a?(String) && bundle["sources"].is_a?(Hash)
      raise ArgumentError, "compile requires bundle.entry and bundle.sources"
    end
    bundle
  end

  def with_frozen_time(time)
    original = Time.method(:now)
    Time.define_singleton_method(:now) { time }
    yield
  ensure
    Time.define_singleton_method(:now, original) if original
  end

  def liquid_error(phase, exception)
    {
      "phase" => phase,
      "code" => exception.class.name,
      "message" => exception.message.to_s,
      "causes" => [],
    }
  end

  def rpc_result(id, result)
    { "jsonrpc" => "2.0", "id" => id, "result" => result }
  end

  def rpc_error(id, code, message)
    { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message } }
  end

  # ── typed values ───────────────────────────────────────────────────────────
  #
  # Ordinary JSON values pass through. Non-JSON values use the collision-safe
  # envelope: { "$liquid-spec": { "type": "...", ... } }.

  def decode_value(value)
    case value
    when Array
      value.map { |child| decode_value(child) }
    when Hash
      if (envelope = value["$liquid-spec"])
        decode_envelope(envelope)
      else
        value.transform_values { |child| decode_value(child) }
      end
    else
      value
    end
  end

  def decode_envelope(envelope)
    case envelope.fetch("type")
    when "bytes"   then Base64.strict_decode64(envelope.fetch("base64"))
    when "symbol"  then envelope.fetch("value").to_sym
    when "integer" then Integer(envelope.fetch("value"))
    when "float"   then decode_float(envelope.fetch("value"))
    when "date", "time", "datetime" then envelope.fetch("value")
    when "range"
      Range.new(
        decode_value(envelope.fetch("start")),
        decode_value(envelope.fetch("end")),
        envelope.fetch("exclusive", false),
      )
    when "map"
      envelope.fetch("entries").to_h do |entry|
        [decode_value(entry.fetch("key")), decode_value(entry.fetch("value"))]
      end
    when "object"  then decode_value(envelope.fetch("value"))
    when "fixture" then Fixtures.build(envelope, method(:decode_value))
    else
      raise ArgumentError, "unknown typed value #{envelope["type"].inspect}"
    end
  end

  def decode_float(raw)
    case raw.to_s
    when "nan"               then Float::NAN
    when "positive_infinity" then Float::INFINITY
    when "negative_infinity" then -Float::INFINITY
    else Float(raw)
    end
  end

  # Partial lookup for include/render. Sources were already compiled; syntax
  # errors surface when the partial is first read.
  class BundleFileSystem
    def initialize(sources, deferred)
      @sources = sources
      @deferred = deferred
    end

    def read_template_file(path)
      key = path.to_s
      bare = key.sub(/\.liquid\z/, "")
      raise @deferred[key] if @deferred.key?(key)
      raise @deferred[bare] if @deferred.key?(bare)
      return @sources[key] if @sources.key?(key)
      return @sources[bare] if @sources.key?(bare)

      raise Liquid::FileSystemError, "Could not find template '#{path}'"
    end
  end
end

# ── fixtures ─────────────────────────────────────────────────────────────────
#
# Two catalogs:
#   standard-drops  — portable drops every adapter should reimplement
#                     (docs: `liquid-spec docs test-drops`)
#   ruby-compat     — reference-only fixtures for Shopify/liquid edge cases
#
# The loader tags each fixture with its set. Unknown names are hard errors so
# a missing fixture never silently becomes a plain hash.

module Fixtures
  module_function

  def build(envelope, decode)
    name = envelope.fetch("name")
    params = decode.call(envelope.fetch("params", {}))
    set = envelope.fetch("set", "standard-drops")

    case set
    when "standard-drops" then standard(name, params)
    when "ruby-compat"    then ruby_compat(name, params)
    else
      raise ArgumentError, "unknown fixture set #{set.inspect}"
    end
  end

  def standard(name, params)
    case name
    when "BooleanDrop"  then Standard::BooleanDrop.new(param(params, "value", false))
    when "NumberDrop"   then Standard::NumberDrop.new(param(params, "value", 0))
    when "StringDrop"   then Standard::StringDrop.new(param(params, "value", ""))
    when "MethodDrop"   then Standard::MethodDrop.new
    when "IndexDrop"    then Standard::IndexDrop.new
    when "SequenceDrop" then Standard::SequenceDrop.new
    when "NilDrop"      then Standard::NilDrop.new
    when "OpaqueDrop"   then Standard::OpaqueDrop.new
    when "ErrorDrop"    then Standard::ErrorDrop.new
    when "NestedDrop"   then Standard::NestedDrop.new(params.is_a?(Hash) ? params : {})
    else
      raise ArgumentError, "unknown standard-drops fixture #{name.inspect}"
    end
  end

  def ruby_compat(name, params)
    case name
    when "ValueDrop"              then Compat::ValueDrop.new(params)
    when "CountingDrop"           then Compat::CountingDrop.new(params)
    when "ToSDrop"                then Compat::ToSDrop.new(params)
    when "TestDrop"               then Compat::TestDrop.new(params)
    when "TestEnumerable"         then Compat::TestEnumerable.new(params)
    when "NumberLikeThing"        then Compat::NumberLikeThing.new(params)
    when "ThingWithToLiquid"      then Compat::ThingWithToLiquid.new
    when "ThingWithValue"         then Compat::ThingWithValue.new
    when "BooleanDrop"            then Compat::BooleanDrop.new(params)
    when "IntegerDrop"            then Compat::IntegerDrop.new(params)
    when "StringDrop"             then Compat::StringDrop.new(params)
    when "ErrorDrop"              then Compat::ErrorDrop.new
    when "SettingsDrop"           then Compat::SettingsDrop.new(params)
    when "CustomToLiquidDrop"     then Compat::CustomToLiquidDrop.new(params)
    when "HashWithCustomToS"      then Compat::HashWithCustomToS.new(params)
    when "HashWithoutCustomToS"   then Compat::HashWithoutCustomToS.new(params)
    when "StubTemplateFactory"    then Compat::StubTemplateFactory.new
    when "LoaderDrop"             then Compat::LoaderDrop.new(params)
    when "ArrayDrop"              then Compat::ArrayDrop.new(params)
    when "LongString"             then "X" * Integer(param(params, "length", 0))
    when "SecurityVictimDrop"     then Compat::SecurityVictimDrop.new(params)
    when "SecurityNestedDrop"     then Compat::SecurityNestedDrop.new
    when "SecurityEnumerableDrop" then Compat::SecurityEnumerableDrop.new
    when "WideOpenObject"         then Compat::WideOpenObject.new
    when "UnsafeHashLikeObject"   then Compat::UnsafeHashLikeObject.new
    when "SafeProxyObject"        then Compat::SafeProxyObject.new
    when "FakeDropObject"         then Compat::FakeDropObject.new
    when "ToLiquidHashObject"     then Compat::ToLiquidHashObject.new
    when "ToLiquidStringObject"   then Compat::ToLiquidStringObject.new
    when "ToLiquidArrayObject"    then Compat::ToLiquidArrayObject.new
    when "ToLiquidNilObject"      then Compat::ToLiquidNilObject.new
    when "Range"                  then Compat.range(params)
    when "LiquidDropClass"        then Liquid::Drop
    when "SafeBuffer"
      value = param(params, "value", "").to_s
      value.respond_to?(:html_safe) ? value.html_safe : value
    else
      raise ArgumentError, "unknown ruby-compat fixture #{name.inspect}"
    end
  end

  def param(params, key, default)
    return default unless params.is_a?(Hash)

    params.key?(key) ? params[key] : default
  end

  # Portable standard-drops catalog. Keep these deterministic and tiny: they are
  # the contract non-Ruby adapters reimplement natively.
  module Standard
    class BooleanDrop < Liquid::Drop
      def initialize(value) = @value = value
      def to_liquid_value = @value
      def to_s = @value.to_s
    end

    class NumberDrop < Liquid::Drop
      def initialize(value) = @value = value
      def to_liquid_value = @value
      def to_number = @value
      def to_s = @value.to_s
    end

    class StringDrop < Liquid::Drop
      def initialize(value) = @value = value
      def to_liquid_value = @value
      def to_s = @value.to_s
    end

    class MethodDrop < Liquid::Drop
      def liquid_method_missing(name)
        operation, number = name.to_s.split("_", 2)
        number = Integer(number)
        case operation
        when "echo"   then number.to_s
        when "square" then (number * number).to_s
        when "double" then (number * 2).to_s
        end
      end
    end

    class IndexDrop < Liquid::Drop
      WORDS = %w[zero one two].freeze
      def [](key) = key.is_a?(Integer) ? WORDS[key] : key.to_s
    end

    class SequenceDrop < Liquid::Drop
      ITEMS = %w[first second third].freeze
      def to_a = ITEMS
      def each(&block) = ITEMS.each(&block)
      def [](key)
        case key.to_s
        when "size"  then ITEMS.size
        when "first" then ITEMS.first
        when "last"  then ITEMS.last
        end
      end
    end

    class NilDrop < Liquid::Drop
      def to_liquid_value = nil
    end

    class OpaqueDrop < Liquid::Drop
      def to_s = "opaque"
    end

    class ErrorDrop < Liquid::Drop
      def liquid_method_missing(*) = raise "standard ErrorDrop access"
    end

    class NestedDrop < Liquid::Drop
      def initialize(params) = @params = params
      def [](key) = @params[key.to_s]
      def liquid_method_missing(name) = @params[name.to_s]
    end
  end

  # Ruby/reference-only fixtures. Prefer standard-drops for new portable specs.
  module Compat
    module_function

    def range(params)
      if params.is_a?(Array)
        Range.new(params[0], params[1])
      elsif params.is_a?(Hash)
        Range.new(params["begin"] || params["start"], params["end"])
      else
        params
      end
    end

    class ValueDrop < Liquid::Drop
      def initialize(value) = @value = value
      def to_s = @value.to_s
      def to_liquid_value = @value
      def liquid_method_missing(method)
        raise Liquid::UndefinedDropMethod, "ValueDrop does not support method '#{method}'"
      end
      def [](key)
        raise Liquid::UndefinedDropMethod, "ValueDrop does not support key access '#{key}'"
      end
    end

    class CountingDrop < Liquid::Drop
      def initialize(_params = {}) = @access_count = 0
      def to_s = "#{@access_count} accesses"
      def [](_property)
        @access_count += 1
        to_s
      end
    end

    class ToSDrop < Liquid::Drop
      def initialize(params = {})
        params = { "to_s" => params } unless params.is_a?(Hash)
        if params.key?("to_s")
          @to_s_value = params["to_s"]
          @initial_foo = nil
        elsif params.key?("foo")
          @initial_foo = params["foo"]
          @call_count = 0
          @to_s_value = nil
        else
          @to_s_value = ""
          @initial_foo = nil
        end
      end

      def to_s
        @initial_foo ? "woot: #{@initial_foo + @call_count}" : @to_s_value.to_s
      end

      def to_liquid
        @call_count += 1 if @initial_foo
        self
      end

      def [](_key) = to_s
    end

    class TestDrop < Liquid::Drop
      def initialize(params = {})
        params = { "value" => params } unless params.is_a?(Hash)
        @value = params["value"]
      end
      attr_reader :value
      def registers = { @value => @context.registers[@value] }
    end

    class TestEnumerable < Liquid::Drop
      include Enumerable
      def initialize(_params = {}) = nil
      def each(&block)
        [
          { "foo" => 1, "bar" => 2 },
          { "foo" => 2, "bar" => 1 },
          { "foo" => 3, "bar" => 3 },
        ].each(&block)
      end
    end

    class NumberLikeThing < Liquid::Drop
      def initialize(params = {})
        params = { "amount" => params } unless params.is_a?(Hash)
        @amount = params["amount"] || 0
      end
      def to_number = @amount
      def to_liquid_value = @amount
    end

    class ThingWithToLiquid
      def to_liquid = "foobar"
    end

    class ThingWithValue < Liquid::Drop
      def value = 3
    end

    class BooleanDrop < Liquid::Drop
      def initialize(params = {})
        params = { "value" => params } unless params.is_a?(Hash)
        @value = params.key?("value") ? params["value"] : false
      end
      def ==(other) = @value == other
      def to_liquid_value = @value
      def to_s = @value ? "Yay" : "Nay"
    end

    class IntegerDrop < Liquid::Drop
      def initialize(params = {})
        params = { "value" => params } unless params.is_a?(Hash)
        @value = (params["value"] || 0).to_i
      end
      def ==(other) = @value == other
      def to_s = @value.to_s
      def to_liquid_value = @value
    end

    class StringDrop < Liquid::Drop
      include Comparable
      def initialize(params = {})
        params = { "value" => params } unless params.is_a?(Hash)
        @value = params["value"]
      end
      def to_liquid_value = @value
      def to_s = @value
      def to_str = @value
      def <=>(other) = to_liquid_value <=> Liquid::Utils.to_liquid_value(other)
    end

    class ErrorDrop < Liquid::Drop
      def standard_error = raise(Liquid::StandardError, "standard error")
      def argument_error = raise(Liquid::ArgumentError, "argument error")
      def syntax_error = raise(Liquid::SyntaxError, "syntax error")
      def runtime_error = raise("runtime error")
      def exception = raise(Exception, "exception")
    end

    class SettingsDrop < Liquid::Drop
      def initialize(params = {})
        @settings = if params.is_a?(Hash) && params.key?("settings")
          params["settings"]
        else
          params
        end
      end
      def liquid_method_missing(key) = @settings[key.to_s] || @settings[key.to_sym]
    end

    class CustomToLiquidDrop < Liquid::Drop
      def initialize(params = {})
        params = { "value" => params } unless params.is_a?(Hash)
        @value = params["value"]
      end
      def to_liquid = @value
    end

    class HashWithCustomToS < Hash
      def self.new(params = {})
        hash = allocate
        hash.merge!(params) if params.is_a?(Hash)
        hash
      end
      def to_s = "kewl"
    end

    class HashWithoutCustomToS < Hash
      def self.new(params = {})
        hash = allocate
        if params.is_a?(Hash)
          params.each { |key, value| hash[key.to_sym] = value.is_a?(String) ? value.to_sym : value }
        end
        hash
      end
    end

    class StubTemplateFactory
      def initialize = @call_count = 0
      def count = @call_count
      def for(template_name)
        @call_count += 1
        template = Liquid::Template.new
        template.name = "some/path/#{template_name}"
        template
      end
    end

    class LoaderDrop < Liquid::Drop
      attr_accessor :each_called, :load_slice_called
      def initialize(params = {})
        params = { "data" => params } unless params.is_a?(Hash)
        @data = params["data"] || []
        @each_called = false
        @load_slice_called = false
      end
      def each(&block)
        @each_called = true
        @data.each(&block)
      end
      def load_slice(from, to)
        @load_slice_called = true
        @data[from...to]
      end
    end

    class ArrayDrop < Liquid::Drop
      include Enumerable
      def initialize(params = {})
        params = { "array" => params } unless params.is_a?(Hash)
        @array = params["array"] || []
      end
      def each(&block) = @array.each(&block)
    end

    class SecurityVictimDrop < Liquid::Drop
      def initialize(params = {})
        params = { "name" => params } unless params.is_a?(Hash)
        @name = params["name"] || "Widget"
        @secret = "TOP_SECRET_API_KEY"
        @internal_state = { "db_password" => "hunter2" }
      end
      def name = @name
      def price = 42
    end

    class SecurityNestedDrop < Liquid::Drop
      def child = SecurityVictimDrop.new("name" => "nested_child")
      def items
        [SecurityVictimDrop.new("name" => "a"), SecurityVictimDrop.new("name" => "b")]
      end
    end

    class SecurityEnumerableDrop < Liquid::Drop
      include Enumerable
      def each(&block) = [1, 2, 3].each(&block)
      def title = "my list"
    end

    class WideOpenObject
      def name = "wide_open"
      def secret = "TOP_SECRET"
      def system_call = "pwned"
    end

    class UnsafeHashLikeObject
      def [](key)
        send(key)
      rescue StandardError
        nil
      end
      def secret = "LEAKED_VIA_BRACKET"
      def name = "unsafe"
    end

    class SafeProxyObject
      def to_liquid = { "name" => "proxied", "safe" => true }
      def secret = "NEVER_SEE_THIS"
    end

    class FakeDropObject
      def to_liquid = self
      def name = "fake_drop"
      def secret = "FAKE_SECRET"
    end

    class ToLiquidHashObject
      def to_liquid = { "name" => "from_to_liquid", "status" => "ok" }
    end

    class ToLiquidStringObject
      def to_liquid = "i_am_a_string"
    end

    class ToLiquidArrayObject
      def to_liquid = [10, 20, 30]
    end

    class ToLiquidNilObject
      def to_liquid = nil
    end
  end
end

# ── entrypoint ───────────────────────────────────────────────────────────────

LiquidRubyReferenceAdapter.new.run if $PROGRAM_NAME == __FILE__
