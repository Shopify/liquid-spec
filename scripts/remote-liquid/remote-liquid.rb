#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Standalone JSON-RPC Liquid Server
#
# Implements the liquid-spec JSON-RPC protocol for testing Liquid implementations.
# See docs/json-rpc-protocol.md for the full specification.
#
# Key design principles:
# - Liquid errors are NOT protocol errors (they go in result.errors)
# - Render always returns {output, errors}
# - Helpful error messages for common mistakes
# - Time freezing support for deterministic tests
#

require "json"
require "liquid"
require "time"

module RemoteLiquid
  VERSION = "1.0"

  # JSON-RPC 2.0 error codes (only for protocol failures, not Liquid errors)
  module ErrorCode
    JSON_PARSE = -32700      # Invalid JSON
    INVALID_REQUEST = -32600 # Missing jsonrpc/method
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602  # Parameter validation failed
  end

  # Hash-based filesystem for {% include %} and {% render %}
  class HashFileSystem
    def initialize(templates = {})
      @templates = normalize_keys(templates)
    end

    def read_template_file(path)
      normalized = normalize_path(path)
      content = @templates[normalized]
      raise Liquid::FileSystemError, "Could not find template '#{path}'" unless content
      content
    end

    private

    def normalize_keys(hash)
      hash.transform_keys { |k| normalize_path(k) }
    end

    def normalize_path(path)
      path = path.to_s.downcase
      path = "#{path}.liquid" unless path.end_with?(".liquid")
      path
    end
  end

  # Proxy for RPC drops - calls back to parent process for property access
  # Note: We deliberately don't include Enumerable because its #first/#last methods
  # would interfere with Liquid's filters. We only define each/to_a for iteration.
  class RpcDropProxy < Liquid::Drop
    def initialize(drop_id, type, server)
      @drop_id = drop_id
      @type = type
      @server = server
      @cache = {}
    end

    def [](key)
      fetch_property(key.to_s)
    end

    def liquid_method_missing(method)
      fetch_property(method.to_s)
    end

    def each(&block)
      items = @server.request_drop_iterate(@drop_id)
      return enum_for(:each) unless block_given?
      items&.each(&block)
    end

    def to_a
      @server.request_drop_iterate(@drop_id) || []
    end

    # Liquid's render tag checks respond_to?(:count) to determine iterability
    # We must define count explicitly since we don't include Enumerable
    # Only return a count if the drop is actually iterable (has items)
    def count
      items = @server.request_drop_iterate(@drop_id)
      items&.count || 0
    end

    # Note: We deliberately do NOT define size here.
    # - For the `size` filter, Liquid::Drop returns 0 when size isn't defined
    # - For iterability checks, `count` is what matters
    # - If the real drop has a `size` method, it will be called via [] or liquid_method_missing

    def to_s
      result = fetch_property("to_s")
      result.nil? ? "[RpcDrop:#{@type}]" : result.to_s
    end

    # Methods that Liquid calls directly on drops (not via [])
    # Only define methods that MUST return a value (to_s, to_number, to_liquid_value)
    # Don't define size/first/last - let Liquid's filters handle the fallback
    def to_number
      fetch_property("to_number")
    end

    def to_liquid_value
      fetch_property("to_liquid_value")
    end

    def blank?
      result = fetch_property("blank?")
      result.nil? ? false : result
    end

    def inspect
      "#<RpcDropProxy:#{@drop_id} type=#{@type}>"
    end

    private

    def fetch_property(property)
      return @cache[property] if @cache.key?(property)
      result = @server.request_drop_property(@drop_id, property)
      # Don't cache errors - they shouldn't be cached anyway
      @cache[property] = result unless result.nil?
      result
    end
  end

  # Main JSON-RPC server
  class Server
    def initialize
      @templates = {}
      @filesystems = {}
      @next_id = 0
      @running = true
    end

    def run
      log("Starting server (liquid #{Liquid::VERSION})...")
      $stdout.sync = true
      $stdin.sync = true

      while @running && (line = $stdin.gets)
        process_line(line)
      end
    rescue IOError => e
      log("IO error: #{e.message}")
    ensure
      log("Exiting")
    end

    # Drop callback: get property
    def request_drop_property(drop_id, property)
      response = send_callback("drop_get", {
        "drop_id" => drop_id,
        "property" => property,
      })
      return nil if response.nil?

      result = response["result"]
      return nil if result.nil?

      # If the callback returned an error (e.g., the drop method raised), propagate it
      # Error is in result.error, not response.error (JSON-RPC success with error payload)
      if result["error"]
        error_message = result.dig("error", "message") || "Drop error"
        raise Liquid::Error, error_message
      end

      unwrap_value(result["value"])
    end

    # Drop callback: iterate
    def request_drop_iterate(drop_id)
      response = send_callback("drop_iterate", { "drop_id" => drop_id })
      return [] if response.nil? || response["error"]
      items = response.dig("result", "items") || []
      items.map { |item| unwrap_value(item) }
    end

    # Drop callback: method call
    def request_drop_call(drop_id, method_name, args = [])
      response = send_callback("drop_call", {
        "drop_id" => drop_id,
        "method" => method_name,
        "args" => args,
      })
      return nil if response.nil? || response["error"]
      unwrap_value(response.dig("result", "value"))
    end

    private

    def send_callback(method, params)
      request = {
        "jsonrpc" => "2.0",
        "id" => next_id,
        "method" => method,
        "params" => params,
      }
      $stdout.puts(JSON.generate(request))
      $stdout.flush

      response_line = $stdin.gets
      return nil unless response_line
      JSON.parse(response_line)
    rescue JSON::ParserError => e
      log("Failed to parse callback response: #{e.message}")
      nil
    end

    def process_line(line)
      request = JSON.parse(line.chomp)
      response = handle_request(request)
      if response
        $stdout.puts(JSON.generate(response))
        $stdout.flush
      end
    rescue JSON::ParserError => e
      log("Invalid JSON: #{e.message}")
      send_error(nil, ErrorCode::JSON_PARSE, "Invalid JSON: #{e.message}")
    end

    def handle_request(request)
      # Validate JSON-RPC structure
      unless request.is_a?(Hash) && request["jsonrpc"] == "2.0"
        return error_response(request&.dig("id"), ErrorCode::INVALID_REQUEST,
          "Invalid request: missing or invalid 'jsonrpc' field")
      end

      id = request["id"]
      method = request["method"]
      params = request["params"] || {}

      # Notifications (no id) don't get responses
      if method == "quit"
        log("Quit received")
        @running = false
        return nil
      end

      unless method.is_a?(String)
        return error_response(id, ErrorCode::INVALID_REQUEST,
          "Invalid request: 'method' must be a string")
      end

      case method
      when "initialize"
        success_response(id, handle_initialize(params))
      when "compile"
        success_response(id, handle_compile(params))
      when "render"
        success_response(id, handle_render(params))
      else
        error_response(id, ErrorCode::METHOD_NOT_FOUND,
          "Unknown method '#{method}'. Valid methods: initialize, compile, render, quit")
      end
    rescue => e
      log("Unexpected error: #{e.class}: #{e.message}")
      log(e.backtrace.first(3).join("\n")) if e.backtrace
      error_response(request&.dig("id"), ErrorCode::INVALID_PARAMS, e.message)
    end

    def handle_initialize(params)
      log("Initialized (protocol #{params["version"] || "1.0"})")
      {
        "version" => VERSION,
        "implementation" => "remote-liquid",
        "liquid_version" => Liquid::VERSION,
        "features" => ["core", "runtime_drops"],
      }
    end

    def handle_compile(params)
      # Validate required params
      template_source = params["template"]
      unless template_source.is_a?(String)
        raise ArgumentError, "Missing or invalid 'template' parameter (expected string)"
      end

      options = params["options"] || {}
      filesystem = params["filesystem"] || {}

      # Validate options
      if options["error_mode"] && !%w[strict lax warn].include?(options["error_mode"])
        raise ArgumentError, "Invalid error_mode '#{options["error_mode"]}': expected 'strict', 'lax', or 'warn'"
      end

      template_id = "tmpl_#{next_id}"

      # Store filesystem
      @filesystems[template_id] = HashFileSystem.new(filesystem)

      # Build parse options
      parse_options = {}
      parse_options[:line_numbers] = true if options["line_numbers"]
      parse_options[:error_mode] = options["error_mode"]&.to_sym

      # Parse template - capture parse errors in result, not as exception
      begin
        template = Liquid::Template.parse(template_source, **parse_options)
        @templates[template_id] = template
        log("Compiled #{template_id}")
        { "template_id" => template_id, "error" => nil }
      rescue Liquid::SyntaxError => e
        log("Parse error: #{e.message}")
        {
          "template_id" => nil,
          "error" => {
            "type" => "syntax_error",
            "message" => e.message,
            "line" => e.respond_to?(:line_number) ? e.line_number : nil,
          },
        }
      end
    end

    def handle_render(params)
      # Validate required params
      template_id = params["template_id"]
      unless template_id.is_a?(String) && @templates.key?(template_id)
        known = @templates.keys.join(", ")
        hint = @templates.empty? ? "Call compile first." : "Known: #{known}"
        raise ArgumentError, "Unknown template_id '#{template_id}'. #{hint}"
      end

      template = @templates[template_id]
      environment = params["environment"] || {}
      options = params["options"] || {}
      frozen_time = params["frozen_time"]

      # Unwrap RPC drops
      unwrapped_env = unwrap_environment(environment)

      # Build registers
      registers = {}
      registers[:file_system] = @filesystems[template_id]

      # Build context - never rethrow errors, we capture them
      context = Liquid::Context.build(
        static_environments: unwrapped_env,
        registers: Liquid::Registers.new(registers),
        rethrow_errors: false
      )

      # Handle time freezing
      output = if frozen_time
        freeze_time(frozen_time) { template.render(context) }
      else
        template.render(context)
      end

      # Collect errors from context
      errors = context.errors.map do |err|
        {
          "type" => error_type(err),
          "message" => err.message.sub(/^Liquid error[^:]*: /, ""),
          "line" => err.respond_to?(:line_number) ? err.line_number : nil,
        }
      end

      # Ensure output is valid UTF-8 for JSON encoding
      output = sanitize_for_json(output)

      log("Rendered #{template_id}: #{output.length} chars, #{errors.length} errors")
      { "output" => output, "errors" => errors }
    end

    # Convert string to valid UTF-8 for JSON encoding
    # Binary data (e.g., from base64_decode) gets replacement characters
    def sanitize_for_json(str)
      return str if str.nil?
      return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

      str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
    end

    def error_type(err)
      case err
      when Liquid::SyntaxError then "syntax_error"
      when Liquid::ArgumentError then "argument_error"
      when Liquid::FileSystemError then "file_system_error"
      when Liquid::MemoryError then "memory_error"
      when Liquid::Error then "liquid_error"
      else "error"
      end
    end

    def freeze_time(iso_time)
      time = Time.iso8601(iso_time)
      # Stub Time.now for the duration of the block
      original_now = Time.method(:now)
      Time.define_singleton_method(:now) { time }
      yield
    ensure
      Time.define_singleton_method(:now, original_now) if original_now
    end

    def unwrap_environment(env)
      case env
      when Hash
        if env["_rpc_drop"]
          RpcDropProxy.new(env["_rpc_drop"], env["type"], self)
        else
          env.transform_values { |v| unwrap_environment(v) }
        end
      when Array
        env.map { |v| unwrap_environment(v) }
      else
        env
      end
    end

    def unwrap_value(value)
      case value
      when Hash
        if value["_rpc_drop"]
          RpcDropProxy.new(value["_rpc_drop"], value["type"], self)
        else
          value.transform_values { |v| unwrap_value(v) }
        end
      when Array
        value.map { |v| unwrap_value(v) }
      else
        value
      end
    end

    def success_response(id, result)
      { "jsonrpc" => "2.0", "id" => id, "result" => result }
    end

    def error_response(id, code, message, data = nil)
      error = { "code" => code, "message" => message }
      error["data"] = data if data
      { "jsonrpc" => "2.0", "id" => id, "error" => error }
    end

    def send_error(id, code, message)
      $stdout.puts(JSON.generate(error_response(id, code, message)))
      $stdout.flush
    end

    def next_id
      @next_id += 1
    end

    def log(message)
      $stderr.puts "[remote-liquid] #{message}" if ENV["VERBOSE"]
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RemoteLiquid::Server.new.run
end
