# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "minitest/autorun"
require "minitest/pride"

# Load liquid-spec components (ClassRegistry is in spec_loader)
require "liquid/spec"
require "liquid/spec/lazy_spec"
require "liquid/spec/spec_loader"

# Load JSON-RPC components
require "liquid/spec/json_rpc/protocol"
require "liquid/spec/json_rpc/drop_proxy"
require "liquid/spec/json_rpc/subprocess"
require "liquid/spec/json_rpc/adapter"

module Liquid
  module Spec
    module TestHelpers
      # Create a temporary YAML spec file
      def with_temp_spec_file(content)
        require "tempfile"
        file = Tempfile.new(["spec", ".yml"])
        file.write(content)
        file.close
        yield file.path
      ensure
        file&.unlink
      end

      # Create a LazySpec from a hash
      def create_spec(attrs = {})
        defaults = {
          name: "test_spec",
          template: "{{ x }}",
          expected: "hello",
        }
        LazySpec.new(**defaults.merge(attrs))
      end
    end
  end
end
