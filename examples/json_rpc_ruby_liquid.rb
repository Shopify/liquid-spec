#!/usr/bin/env ruby
# frozen_string_literal: true

#
# JSON-RPC adapter for testing liquid-ruby over the JSON-RPC protocol
#
# This adapter spawns scripts/remote-liquid/remote-liquid.rb as a subprocess
# and communicates with it via JSON-RPC. The remote script uses the liquid gem
# but relies entirely on JSON-RPC callbacks for drop access.
#
# Run: liquid-spec examples/json_rpc_ruby_liquid.rb
#

require "liquid/spec/cli/adapter_dsl"
require "liquid/spec/json_rpc/adapter"

REMOTE_LIQUID_PATH = File.expand_path("../scripts/remote-liquid/remote-liquid.rb", __dir__)

# Find the liquid library path from $LOAD_PATH (allows -I flag to specify custom liquid)
LIQUID_LIB_PATH = $LOAD_PATH.find { |p| File.exist?(File.join(p, "liquid.rb")) }

LiquidSpec.setup do |ctx|
  unless File.exist?(REMOTE_LIQUID_PATH)
    raise "Remote liquid server not found at #{REMOTE_LIQUID_PATH}"
  end

  # Load Liquid locally for test drop classes (ClassRegistry needs Liquid::Drop)
  # The actual template compilation/rendering happens in the remote subprocess
  require "liquid"

  # Pass the liquid library path to the subprocess so it uses the same version
  ruby_cmd = if LIQUID_LIB_PATH
    "ruby -I#{LIQUID_LIB_PATH} #{REMOTE_LIQUID_PATH}"
  else
    "ruby #{REMOTE_LIQUID_PATH}"
  end

  ctx[:adapter] = Liquid::Spec::JsonRpc::Adapter.new(
    ruby_cmd,
    timeout: 5
  )
  ctx[:adapter].start
end

LiquidSpec.configure do |config|
  # JSON-RPC adapters support core features including runtime_drops
  # because they implement bidirectional callbacks
  config.features = [:core, :strict_parsing]
end

LiquidSpec.compile do |ctx, source, parse_options|
  ctx[:template_id] = ctx[:adapter].compile(source, parse_options)
end

LiquidSpec.render do |ctx, assigns, render_options|
  ctx[:adapter].render(ctx[:template_id], assigns, render_options)
end
