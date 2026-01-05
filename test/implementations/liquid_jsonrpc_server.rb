#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone JSON-RPC server implementation for testing
# Uses the standard Liquid gem and implements the liquid-spec JSON-RPC protocol

require "json"
require "liquid"

class LiquidJsonRpcServer
  def initialize
    @templates = {}
    @filesystems = {}
    @next_id = 0
    @running = true
  end

  def run
    $stderr.puts "[LiquidJsonRpcServer] Starting..."
    $stdout.sync = true
    $stdin.sync = true

    while @running && (line = $stdin.gets)
      begin
        request = JSON.parse(line.chomp)
        response = handle_request(request)
        $stdout.puts(JSON.generate(response))
        $stdout.flush
      rescue JSON::ParserError => e
        $stderr.puts "[LiquidJsonRpcServer] JSON parse error: #{e.message}"
      end
    end
  rescue IOError => e
    $stderr.puts "[LiquidJsonRpcServer] IO error: #{e.message}"
  ensure
    $stderr.puts "[LiquidJsonRpcServer] Exiting..."
  end

  # For RPC drops to call back to the client
  def request_drop_property(drop_id, property)
    request = {
      "jsonrpc" => "2.0",
      "id" => @next_id += 1,
      "method" => "drop_get",
      "params" => { "drop_id" => drop_id, "property" => property },
    }

    $stdout.puts(JSON.generate(request))
    $stdout.flush

    response_line = $stdin.gets
    return nil unless response_line

    response = JSON.parse(response_line)

    if response["error"]
      raise response["error"]["message"]
    end

    unwrap_value(response["result"]["value"])
  end

  private

  def handle_request(request)
    id = request["id"]
    method = request["method"]
    params = request["params"] || {}

    result = case method
    when "initialize"
      handle_initialize(params)
    when "shutdown"
      handle_shutdown(params)
    when "compile"
      handle_compile(params)
    when "render"
      handle_render(params)
    else
      return error_response(id, -32601, "Method not found: #{method}")
    end

    success_response(id, result)
  rescue Liquid::SyntaxError => e
    error_response(id, -32000, "Parse error", {
      "type" => "parse_error",
      "message" => e.message,
      "line" => e.respond_to?(:line_number) ? e.line_number : nil,
    })
  rescue Liquid::FileSystemError => e
    error_response(id, -32001, "Render error", {
      "type" => "render_error",
      "message" => e.message,
    })
  rescue Liquid::Error => e
    error_response(id, -32001, "Render error", {
      "type" => "render_error",
      "message" => e.message,
      "line" => e.respond_to?(:line_number) ? e.line_number : nil,
    })
  rescue StandardError => e
    error_response(id, -32001, "Internal error", {
      "type" => "error",
      "message" => e.message,
    })
  end

  def handle_initialize(params)
    version = params["version"] || "1.0"
    $stderr.puts "[LiquidJsonRpcServer] Initialized with version #{version}"
    {
      "version" => "1.0",
      "features" => ["core"],
      "implementation" => "liquid-ruby",
      "liquid_version" => Liquid::VERSION,
    }
  end

  def handle_shutdown(_params)
    $stderr.puts "[LiquidJsonRpcServer] Shutdown requested"
    @running = false
    {}
  end

  def handle_compile(params)
    template_source = params["template"]
    options = params["options"] || {}
    filesystem = params["filesystem"] || {}

    template_id = "tmpl_#{@next_id += 1}"

    # Build filesystem
    fs = HashFileSystem.new(filesystem)
    @filesystems[template_id] = fs

    # Build parse options
    parse_options = {}
    parse_options[:line_numbers] = true if options["line_numbers"]
    parse_options[:error_mode] = options["error_mode"].to_sym if options["error_mode"]

    # Parse template
    template = Liquid::Template.parse(template_source, **parse_options)
    @templates[template_id] = template

    { "template_id" => template_id }
  end

  def handle_render(params)
    template_id = params["template_id"]
    environment = params["environment"] || {}
    options = params["options"] || {}

    template = @templates[template_id]
    raise "Unknown template: #{template_id}" unless template

    # Unwrap RPC drops in environment
    unwrapped_env = unwrap_environment(environment)

    # Build registers
    registers = {}
    registers[:file_system] = @filesystems[template_id] if @filesystems[template_id]

    # Determine error handling
    rethrow = !options["render_errors"]

    # Build context and render
    context = Liquid::Context.build(
      static_environments: unwrapped_env,
      registers: Liquid::Registers.new(registers),
      rethrow_errors: rethrow
    )

    output = template.render(context)
    { "output" => output }
  end

  def unwrap_environment(env)
    case env
    when Hash
      if env["_rpc_drop"]
        # Create a proxy that calls back to the client
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

  # Simple hash-based filesystem for includes/renders
  class HashFileSystem
    def initialize(templates)
      @templates = normalize_keys(templates || {})
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

  # Proxy for RPC drops that calls back to the client
  class RpcDropProxy < Liquid::Drop
    def initialize(drop_id, type, server)
      @drop_id = drop_id
      @type = type
      @server = server
    end

    def [](key)
      @server.request_drop_property(@drop_id, key.to_s)
    end

    def liquid_method_missing(method)
      @server.request_drop_property(@drop_id, method.to_s)
    end

    def to_s
      "[RpcDrop:#{@type}]"
    end
  end
end

# Run server if executed directly
if __FILE__ == $PROGRAM_NAME
  LiquidJsonRpcServer.new.run
end
