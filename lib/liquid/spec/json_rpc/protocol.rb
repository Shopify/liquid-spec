# frozen_string_literal: true

require "json"

module Liquid
  module Spec
    module JsonRpc
      # JSON-RPC 2.0 protocol implementation
      module Protocol
        VERSION = "2.0"

        # Error codes
        module ErrorCode
          PARSE_ERROR = -32000      # Template parse error
          RENDER_ERROR = -32001     # Template render error
          DROP_ERROR = -32002       # Drop access error
          JSON_PARSE = -32700       # Invalid JSON
          INVALID_REQUEST = -32600  # Invalid request
          METHOD_NOT_FOUND = -32601 # Method not found
        end

        # Build a JSON-RPC request
        def self.request(id:, method:, params: {})
          {
            "jsonrpc" => VERSION,
            "id" => id,
            "method" => method,
            "params" => params,
          }
        end

        # Build a JSON-RPC notification (no response expected)
        def self.notification(method:, params: {})
          {
            "jsonrpc" => VERSION,
            "method" => method,
            "params" => params,
          }
        end

        # Build a JSON-RPC success response
        def self.response(id:, result:)
          {
            "jsonrpc" => VERSION,
            "id" => id,
            "result" => result,
          }
        end

        # Build a JSON-RPC error response
        def self.error_response(id:, code:, message:, data: nil)
          error = {
            "code" => code,
            "message" => message,
          }
          error["data"] = data if data

          {
            "jsonrpc" => VERSION,
            "id" => id,
            "error" => error,
          }
        end

        # Encode a message to JSON line
        def self.encode(msg)
          JSON.generate(msg)
        end

        # Decode a JSON line to message
        def self.decode(line)
          JSON.parse(line)
        rescue JSON::ParserError => e
          raise ProtocolError.new("Invalid JSON: #{e.message}", ErrorCode::JSON_PARSE)
        end

        # Check if message is a request (has method)
        def self.request?(msg)
          msg.key?("method")
        end

        # Check if message is a response (has result or error)
        def self.response?(msg)
          msg.key?("result") || msg.key?("error")
        end

        # Check if response is an error
        def self.error?(msg)
          msg.key?("error")
        end

        # Extract error details from response
        def self.extract_error(msg)
          return nil unless error?(msg)

          error = msg["error"]
          {
            code: error["code"],
            message: error["message"],
            data: error["data"],
          }
        end
      end

      # Protocol-level error
      class ProtocolError < StandardError
        attr_reader :code

        def initialize(message, code = Protocol::ErrorCode::INVALID_REQUEST)
          @code = code
          super(message)
        end
      end
    end
  end
end
