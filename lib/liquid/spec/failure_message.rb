require "tty-box"

module Liquid
  module Spec
    class FailureMessage
      attr_reader :spec, :actual

      Differ = Class.new(Minitest::Assertions)

      def initialize(spec, actual)
        @spec = spec
        @actual = actual
      end

      def to_s
        template = render_box(content: spec.template, name: "Template")
        environment = render_box(content: spec.environment.inspect, name: "Environment")
        rendered_diff = render_box(content: Differ.diff(spec.expected, actual), name: "Diff")

        <<~MSG
          #{template}

          #{environment}

          #{rendered_diff}

          ===========================

          To rerun this spec, run the following command:
            $ rake liquid_spec TESTOPTS="--name=/#{spec.name}"
        MSG
      end

      private

      def render_box(name:, content:)
        TTY::Box.frame(content, width: 80, title: {top_left: name}).strip
      end
    end
  end
end
