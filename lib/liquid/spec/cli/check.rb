# frozen_string_literal: true

require_relative "../verifiers"

module Liquid
  module Spec
    module CLI
      module Check
        HELP = <<~HELP
          Usage: liquid-spec tools check

          Run every verifier in scripts/verifiers. Blocking verifier failures
          produce exit status 1; advisory findings are reported but do not fail.

          This is the same verifier gate used by `rake check`. Use
          `rake prepush` when you also need the liquid-spec unit tests.
        HELP

        def self.run(args)
          if args.include?("-h") || args.include?("--help")
            puts HELP
            return
          end

          unless args.empty?
            $stderr.puts "Error: Unknown check option: #{args.first}"
            exit(2)
          end

          exit Liquid::Spec::Verifiers.run
        end
      end
    end
  end
end
