# frozen_string_literal: true

require_relative "subprocess"
require_relative "drop_proxy"
require_relative "protocol"

module Liquid
  module Spec
    module JsonRpc
      # JSON-RPC adapter for liquid-spec
      # Communicates with a subprocess that implements the Liquid JSON-RPC protocol
      #
      # Protocol design principles:
      # - Liquid errors are NOT protocol errors (they're part of render output)
      # - Compile returns {template_id, error} - error is nil on success
      # - Render returns {output, errors} - always succeeds, errors are informational
      # - Time freezing is supported via frozen_time parameter
      #
      # See docs/json-rpc-protocol.md for the full specification.
      class Adapter
        attr_reader :subprocess

        def initialize(command, timeout: Subprocess::DEFAULT_TIMEOUT)
          @subprocess = Subprocess.new(command, timeout: timeout)
        end

        # Initialize the subprocess connection
        def start
          @subprocess.initialize!
        end

        # Get features supported by the subprocess
        def features
          @subprocess.features
        end

        # Compile a template and return a template_id
        def compile(source, options = {})
          @subprocess.initialize! unless @subprocess.running?

          # Extract and convert filesystem
          filesystem = extract_filesystem(options)

          # Build compile params
          params = {
            "template" => source,
            "options" => serialize_options(options),
          }
          params["filesystem"] = filesystem unless filesystem.empty?

          response = @subprocess.send_request("compile", params)

          # Handle protocol-level errors (invalid params, etc.)
          if Protocol.error?(response)
            raise_protocol_error(response)
          end

          result = response["result"]

          # Handle parse errors (returned in result.error, not as protocol error)
          if result && result["error"]
            raise_compile_error(result["error"])
          end

          result&.dig("template_id")
        end

        # Render a compiled template
        # Returns the output string - Liquid errors are rendered inline, not raised
        def render(template_id, environment, options = {})
          @subprocess.initialize! unless @subprocess.running?

          # Clear drops from previous spec
          @subprocess.clear_drops

          # Wrap environment (converts drops to RPC markers)
          wrapped_env = DropProxy.wrap(environment, @subprocess.drop_registry)

          params = {
            "template_id" => template_id,
            "environment" => wrapped_env,
            "options" => serialize_render_options(options),
          }

          # Pass frozen time if set (for deterministic date/time tests)
          frozen_time = TimeFreezer.frozen_time rescue nil
          if frozen_time
            params["frozen_time"] = frozen_time.iso8601
          end

          response = @subprocess.send_request("render", params)

          # Handle protocol-level errors (invalid params, unknown template_id, etc.)
          if Protocol.error?(response)
            raise_protocol_error(response)
          end

          # Return output - Liquid errors are already rendered inline
          # The errors array is informational for test assertions
          response.dig("result", "output") || ""
        end

        # Shutdown the subprocess
        def shutdown
          @subprocess.shutdown
        end

        private

        def extract_filesystem(options)
          fs = options.delete(:file_system) || options.delete("file_system")
          return {} unless fs

          # Convert filesystem object to hash
          if fs.respond_to?(:to_h)
            fs.to_h.transform_keys(&:to_s)
          elsif fs.is_a?(Hash)
            fs.transform_keys(&:to_s)
          elsif fs.respond_to?(:templates)
            fs.templates.transform_keys(&:to_s)
          else
            {}
          end
        end

        def serialize_options(options)
          result = {}

          if options[:error_mode] || options["error_mode"]
            mode = options[:error_mode] || options["error_mode"]
            result["error_mode"] = mode.to_s
          end

          if options[:line_numbers] || options["line_numbers"]
            result["line_numbers"] = true
          end

          result
        end

        def serialize_render_options(options)
          result = {}

          strict_errors = options[:strict_errors] || options["strict_errors"]
          result["strict_errors"] = !!strict_errors if strict_errors != nil

          result
        end

        # Raise error for compile failures (parse errors)
        def raise_compile_error(error)
          message = error["message"] || "Parse error"

          # Don't double-wrap if message already has Liquid prefix
          if message.start_with?("Liquid")
            raise LiquidSyntaxError, message
          end

          line = error["line"]
          full_message = if line
            "Liquid syntax error (line #{line}): #{message}"
          else
            "Liquid syntax error: #{message}"
          end

          raise LiquidSyntaxError, full_message
        end

        # Raise error for protocol-level failures
        def raise_protocol_error(response)
          error = Protocol.extract_error(response)
          message = error[:message] || "Unknown error"
          data = error[:data]

          # Include helpful context if available
          if data.is_a?(Hash) && data["message"]
            message = "#{message}: #{data["message"]}"
          end

          raise ProtocolError, message
        end
      end

      # Protocol-level error (invalid params, method not found, etc.)
      class ProtocolError < StandardError; end

      # Parse/syntax error from subprocess (class name must contain "SyntaxError" for runner detection)
      class LiquidSyntaxError < StandardError; end
    end
  end
end
