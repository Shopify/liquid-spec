#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

$stdout.sync = true

ARGF.each_line do |line|
  request = JSON.parse(line)
  id = request["id"]

  case request["method"]
  when "initialize"
    puts JSON.generate(
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => { "version" => "1.0", "features" => [] },
    )
  when "stall"
    sleep 60
  when "ping"
    puts JSON.generate(
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => { "value" => "pong" },
    )
  when "quit"
    break
  end
end
