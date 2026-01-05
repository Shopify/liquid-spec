#!/usr/bin/env ruby
# frozen_string_literal: true

# Mock Liquid JSON-RPC server for testing
# Implements the liquid-spec JSON-RPC protocol using the real Liquid gem

require "json"
require "liquid"

class MockLiquidServer
  def initialize
    @templates = {}
    @next_id = 0
    @filesystems = {}
    @drop_callbacks = {}
  end

  def run
    $stderr.puts "[MockServer] Starting..."
    $stdout.sync = true
    $stdin.each_line do |line|
      request = JSON.parse(line.chomp)
      response = handle_request(request)
      $stdout.puts(JSON.generate(response))
      $stdout.flush
    end
  rescue => e
    $stderr.puts "[MockServer] Error: #{e.message}"
    $stderr.puts e.backtrace.first(5).join("\n")
  end

  # Public method for RPC drops to call back
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
    response = JSON.parse(response_line)

    if response["error"]
      raise response["error"]["message"]
    end

    unwrap_environment(response["result"]["value"])
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
      "line" => e.line_number,
      "message" => e.message,
    })
  rescue Liquid::Error => e
    error_response(id, -32001, "Render error", {
      "type" => "render_error",
      "line" => e.respond_to?(:line_number) ? e.line_number : nil,
      "message" => e.message,
    })
  rescue => e
    error_response(id, -32001, "Error", {
      "type" => "error",
      "message" => e.message,
    })
  end

  def handle_initialize(params)
    $stderr.puts "[MockServer] Initialized with version #{params["version"]}"
    { "version" => "1.0", "features" => ["core"] }
  end

  def handle_shutdown(_params)
    $stderr.puts "[MockServer] Shutting down..."
    Thread.new { sleep 0.1; exit(0) }
    {}
  end

  def handle_compile(params)
    template_source = params["template"]
    options = params["options"] || {}
    filesystem = params["filesystem"] || {}

    template_id = "tmpl_#{@next_id += 1}"

    # Store filesystem for this template
    @filesystems[template_id] = SimpleFileSystem.new(filesystem)

    # Parse options
    parse_options = { line_numbers: options["line_numbers"] }
    if options["error_mode"]
      parse_options[:error_mode] = options["error_mode"].to_sym
    end
    parse_options[:file_system] = @filesystems[template_id]

    # Parse the template
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

    # Build context
    registers = {}
    registers[:file_system] = @filesystems[template_id] if @filesystems[template_id]

    context = Liquid::Context.build(
      static_environments: unwrapped_env,
      registers: Liquid::Registers.new(registers),
      rethrow_errors: !options["render_errors"]
    )

    output = template.render(context)
    { "output" => output }
  end

  def unwrap_environment(env)
    case env
    when Hash
      if env["_rpc_drop"]
        # This is an RPC drop - create a proxy that calls back
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

  def success_response(id, result)
    { "jsonrpc" => "2.0", "id" => id, "result" => result }
  end

  def error_response(id, code, message, data = nil)
    error = { "code" => code, "message" => message }
    error["data"] = data if data
    { "jsonrpc" => "2.0", "id" => id, "error" => error }
  end

  # Simple filesystem for includes
  class SimpleFileSystem
    def initialize(templates)
      @templates = (templates || {}).transform_keys do |key|
        key = key.to_s.downcase
        key = "#{key}.liquid" unless key.end_with?(".liquid")
        key
      end
    end

    def read_template_file(path)
      normalized = path.to_s.downcase
      normalized = "#{normalized}.liquid" unless normalized.end_with?(".liquid")
      @templates.find { |k, _| k.casecmp?(normalized) }&.last or
        raise Liquid::FileSystemError, "Could not find asset #{path}"
    end
  end

  # Proxy for RPC drops
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
  end
end

# Run the server
MockLiquidServer.new.run
