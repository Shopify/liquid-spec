# frozen_string_literal: true

module Liquid
  module Spec
    module CLI
      # Measures template-cold workflows in forked children.
      #
      # The coordinator is forked before any benchmark template is compiled. It
      # never invokes adapter hooks itself; each operation runs in a short-lived
      # child, so compiler and artifact caches cannot leak between samples. The
      # timer lives inside that child and therefore excludes fork and IPC costs.
      class ForkBenchmark
        DEFAULT_SAMPLES = 30

        def initialize(specs, samples: DEFAULT_SAMPLES, &operation)
          raise NotImplementedError, "cold benchmarks require Process.fork" unless Process.respond_to?(:fork)

          @samples = samples
          @spec_indices = {}
          specs.each_with_index { |spec, index| @spec_indices[spec.object_id] = index }
          request_reader, @request_writer = IO.pipe
          @response_reader, response_writer = IO.pipe
          [request_reader, @request_writer, @response_reader, response_writer].each(&:binmode)

          @pid = fork do
            @request_writer.close
            @response_reader.close
            serve(request_reader, response_writer, specs, operation)
          ensure
            request_reader.close rescue nil
            response_writer.close rescue nil
            exit! 0
          end

          request_reader.close
          response_writer.close
        end

        def measure(spec, artifact:)
          Marshal.dump([:measure, @spec_indices.fetch(spec.object_id), artifact], @request_writer)
          @request_writer.flush
          response = Marshal.load(@response_reader)
          raise_remote_error(response) if response[:error]
          response
        end

        def close
          return unless @pid

          Marshal.dump([:close], @request_writer)
          @request_writer.flush
          Process.waitpid(@pid)
        rescue Errno::EPIPE, EOFError, Errno::ECHILD
          # The coordinator already exited; there is nothing left to clean up.
        ensure
          @request_writer.close rescue nil
          @response_reader.close rescue nil
          @pid = nil
        end

        private

        def serve(request_reader, response_writer, specs, operation)
          loop do
            command, spec_index, artifact = Marshal.load(request_reader)
            break if command == :close

            spec = specs.fetch(spec_index)
            response = measure_spec(spec, artifact, operation)
            Marshal.dump(response, response_writer)
            response_writer.flush
          rescue EOFError
            break
          rescue Exception => error # rubocop:disable Lint/RescueException
            Marshal.dump({ error: serialize_error(error) }, response_writer)
            response_writer.flush
          end
        end

        def measure_spec(spec, artifact, operation)
          compile_samples, compile_output = sample(@samples) do
            operation.call(spec, :compile_render, nil)
          end
          result = {
            compile_render_samples_ns: compile_samples,
            compile_render_output: compile_output,
          }

          if artifact
            blob = child_call { operation.call(spec, :build_artifact, nil) }
            unless blob.is_a?(String)
              raise TypeError, "dump_artifact must return a String, got #{blob.class}"
            end

            load_samples, load_output = sample(@samples) do
              operation.call(spec, :artifact_load_render, blob)
            end
            result[:artifact_bytes] = blob.bytesize
            result[:artifact_load_render_samples_ns] = load_samples
            result[:artifact_load_render_output] = load_output
          end

          result
        end

        def sample(count)
          expected_output = nil
          samples = Array.new(count) do |index|
            measurement = child_call { yield }
            elapsed_ns = measurement.fetch(:elapsed_ns)
            output = measurement.fetch(:output)
            expected_output ||= output
            if output != expected_output
              raise "forked benchmark output changed between samples (sample #{index + 1})"
            end
            elapsed_ns
          end
          [samples, expected_output]
        end

        def child_call
          reader, writer = IO.pipe
          reader.binmode
          writer.binmode
          pid = fork do
            reader.close
            payload = begin
              { value: yield }
            rescue Exception => error # rubocop:disable Lint/RescueException
              { error: serialize_error(error) }
            end
            Marshal.dump(payload, writer)
            writer.flush
          ensure
            writer.close rescue nil
            exit! 0
          end

          writer.close
          payload = Marshal.load(reader)
          _, status = Process.wait2(pid)
          pid = nil
          unless status.success?
            raise "forked benchmark child exited with #{status.inspect}"
          end
          raise_remote_error(payload) if payload[:error]
          payload[:value]
        ensure
          reader.close rescue nil
          writer.close rescue nil
          Process.waitpid(pid) rescue nil if pid
        end

        def serialize_error(error)
          {
            class: error.class.name,
            message: error.message,
            backtrace: error.backtrace,
          }
        end

        def raise_remote_error(response)
          error = response[:error]
          exception = RuntimeError.new("#{error[:class]}: #{error[:message]}")
          exception.set_backtrace(error[:backtrace])
          raise exception
        end
      end
    end
  end
end
