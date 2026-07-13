# frozen_string_literal: true

require "liquid/spec/cli/adapter_dsl"
require "liquid/spec/json_rpc/adapter"

LiquidSpec.setup do |ctx|
  ctx[:adapter] = Liquid::Spec::JsonRpc::Adapter.new("path/to/your/liquid-server")
  ctx[:adapter].start
end

LiquidSpec.configure do |config|
  config.suite = :basics
end
