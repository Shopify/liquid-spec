# frozen_string_literal: true

require_relative "subprocess"
require_relative "drop_proxy"
require_relative "protocol"

module Liquid
  module Spec
    module JsonRpc
      # JSON-RPC adapter for liquid-spec
      # Communicates with a subprocess that implements the Liquid JSON-RPC protocol
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

          if Protocol.error?(response)
            raise_liquid_error(response)
          end

          response.dig("result", "template_id")
        end

        # Render a compiled template
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

          response = @subprocess.send_request("render", params)

          if Protocol.error?(response)
            raise_liquid_error(response)
          end

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

          render_errors = options[:render_errors] || options["render_errors"]
          result["render_errors"] = !!render_errors if render_errors != nil

          strict_errors = options[:strict_errors] || options["strict_errors"]
          result["strict_errors"] = !!strict_errors if strict_errors != nil

          result
        end

        def raise_liquid_error(response)
          error = Protocol.extract_error(response)
          data = error[:data] || {}
          error_type = data["type"] || "error"
          message = data["message"] || error[:message]
          line = data["line"]

          # Format error message like Liquid does
          full_message = if line
            "Liquid error (line #{line}): #{message}"
          else
            "Liquid error: #{message}"
          end

          case error_type
          when "parse_error"
            raise LiquidParseError, full_message
          when "render_error"
            raise LiquidRenderError, full_message
          else
            raise LiquidError, full_message
          end
        end
      end

      # Base error for Liquid errors from subprocess
      class LiquidError < StandardError; end

      # Parse error from subprocess
      class LiquidParseError < LiquidError; end

      # Render error from subprocess
      class LiquidRenderError < LiquidError; end
    end
  end
end
