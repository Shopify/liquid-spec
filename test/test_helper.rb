# frozen_string_literal: true

require "minitest"
require "minitest/autorun"
require "liquid"
require "json"

# Optional dependencies - load if available
begin
  require "mocha/minitest"
rescue LoadError
  # mocha not available, skip
end

begin
  require "pry-byebug"
rescue LoadError
  # pry-byebug not available, skip
end

require "liquid/spec"
