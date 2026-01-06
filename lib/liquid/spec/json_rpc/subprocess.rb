# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "protocol"
require_relative "drop_proxy"

module Liquid
  module Spec
    module JsonRpc
      # Manages communication with a JSON-RPC subprocess
      class Subprocess
        attr_reader :drop_registry

        DEFAULT_TIMEOUT = 30 # seconds

        def initialize(command, timeout: DEFAULT_TIMEOUT)
          @command = command
          @timeout = timeout
          @request_id = 0
          @drop_registry = DropRegistry.new
          @stdin = nil
          @stdout = nil
          @stderr = nil
          @wait_thr = nil
          @initialized = false
        end

        # Start the subprocess
        def start
          return if running?

          @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@command)

          # Set streams to non-blocking where possible
          @stdout.sync = true
          @stdin.sync = true
        end

        # Check if subprocess is running
        def running?
          @wait_thr&.alive?
        end

        # Initialize the protocol with the subprocess
        def initialize!
          start unless running?
          return if @initialized

          response = send_request("initialize", { "version" => "1.0" })

          unless response["result"]
            raise SubprocessError, "Failed to initialize: #{response["error"]&.dig("message") || "unknown error"}"
          end

          @features = response["result"]["features"] || []
          @initialized = true
        end

        # Get subprocess features
        def features
          @features || []
        end

        # Send a request and wait for response, handling drop callbacks
        def send_request(method, params)
          raise SubprocessError, "Subprocess not running" unless running?

          id = next_id
          msg = Protocol.request(id: id, method: method, params: params)

          write_message(msg)
          read_response_for(id)
        end

        # Shutdown the subprocess
        def shutdown
          return unless running?

          # Send quit notification then immediately kill
          begin
            write_message(Protocol.notification(method: "quit"))
          rescue IOError, Errno::EPIPE
            # Subprocess may have already exited
          end

          # Force kill immediately
          Process.kill("KILL", @wait_thr.pid) rescue nil
          cleanup
        end

        # Clear drop registry between specs
        def clear_drops
          @drop_registry.clear
        end

        private

        def next_id
          @request_id += 1
        end

        def write_message(msg)
          line = Protocol.encode(msg)
          @stdin.puts(line)
          @stdin.flush
        rescue IOError, Errno::EPIPE => e
          raise SubprocessError, "Failed to write to subprocess: #{e.message}"
        end

        def read_response_for(expected_id)
          Timeout.timeout(@timeout) do
            loop do
              line = @stdout.gets
              raise SubprocessError, "Subprocess closed stdout unexpectedly" if line.nil?

              msg = Protocol.decode(line.chomp)

              if Protocol.request?(msg)
                # This is a callback from subprocess (drop access)
                handle_callback(msg)
              elsif msg["id"] == expected_id
                # This is the response we're waiting for
                return msg
              else
                # Unexpected message - log and continue
                warn "Unexpected message with id #{msg["id"]}, expected #{expected_id}"
              end
            end
          end
        rescue Timeout::Error
          raise SubprocessError, "Timeout waiting for response (#{@timeout}s)"
        rescue IOError => e
          raise SubprocessError, "Failed to read from subprocess: #{e.message}"
        end

        def handle_callback(request)
          method = request["method"]
          params = request["params"]
          id = request["id"]

          response = case method
          when "drop_get"
            handle_drop_get(params)
          when "drop_call"
            handle_drop_call(params)
          when "drop_iterate"
            handle_drop_iterate(params)
          else
            Protocol.error_response(
              id: id,
              code: Protocol::ErrorCode::METHOD_NOT_FOUND,
              message: "Unknown callback method: #{method}"
            )
          end

          # Add the id to the response if it's a result hash
          if response.is_a?(Hash) && !response.key?("jsonrpc")
            response = Protocol.response(id: id, result: response)
          elsif response.is_a?(Hash) && response.key?("error")
            response["id"] = id
          end

          write_message(response)
        end

        def handle_drop_get(params)
          drop_id = params["drop_id"]
          property = params["property"]

          drop = @drop_registry[drop_id]
          unless drop
            return { "error" => { "code" => Protocol::ErrorCode::DROP_ERROR, "message" => "Unknown drop: #{drop_id}" } }
          end

          begin
            value = DropProxy.access_drop(drop, property)
            wrapped = DropProxy.wrap(value, @drop_registry)
            { "value" => wrapped }
          rescue => e
            { "error" => { "code" => Protocol::ErrorCode::DROP_ERROR, "message" => e.message } }
          end
        end

        def handle_drop_call(params)
          drop_id = params["drop_id"]
          method_name = params["method"]
          args = params["args"] || []

          drop = @drop_registry[drop_id]
          unless drop
            return { "error" => { "code" => Protocol::ErrorCode::DROP_ERROR, "message" => "Unknown drop: #{drop_id}" } }
          end

          begin
            value = DropProxy.call_drop(drop, method_name, args)
            wrapped = DropProxy.wrap(value, @drop_registry)
            { "value" => wrapped }
          rescue => e
            { "error" => { "code" => Protocol::ErrorCode::DROP_ERROR, "message" => e.message } }
          end
        end

        def handle_drop_iterate(params)
          drop_id = params["drop_id"]

          drop = @drop_registry[drop_id]
          unless drop
            return { "error" => { "code" => Protocol::ErrorCode::DROP_ERROR, "message" => "Unknown drop: #{drop_id}" } }
          end

          begin
            items = DropProxy.iterate_drop(drop)
            wrapped_items = items.map { |item| DropProxy.wrap(item, @drop_registry) }
            { "items" => wrapped_items }
          rescue => e
            { "error" => { "code" => Protocol::ErrorCode::DROP_ERROR, "message" => e.message } }
          end
        end

        def cleanup
          @stdin&.close rescue nil
          @stdout&.close rescue nil
          @stderr&.close rescue nil

          if @wait_thr&.alive?
            Process.kill("TERM", @wait_thr.pid) rescue nil
            @wait_thr.join(2)
            Process.kill("KILL", @wait_thr.pid) rescue nil if @wait_thr.alive?
          end

          @stdin = nil
          @stdout = nil
          @stderr = nil
          @wait_thr = nil
          @initialized = false
        end
      end

      # Error from subprocess communication
      class SubprocessError < StandardError; end
    end
  end
end
