#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone entry point for the verifier gate. The shared implementation also
# powers `liquid-spec tools check` and `rake check`.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "liquid/spec/verifiers"

exit Liquid::Spec::Verifiers.run if $PROGRAM_NAME == __FILE__
