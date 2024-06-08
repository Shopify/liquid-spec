require "tty-box"

module Liquid
  module Spec
    class FailureMessage
      attr_reader :spec, :actual, :width

      def initialize(spec, actual, width: nil)
        @spec = spec
        @actual = actual
        @width = width
      end

      class << self
        def rerun_command_for(spec)
          if defined?(TLDR)
            "bundle exec tldr test/integration/liquid_spec.rb --name=/#{spec.name}/"
          else
            "rake liquid_spec TESTOPTS=\"--name=/#{spec.name}/\""
          end
        end
      end

      def to_s
        return @rendered_message if defined?(@rendered_message)

        template = render_box(content: spec.template, name: "Template")
        environment = render_box(content: spec.environment.inspect, name: "Environment")
        rendered_diff = render_box(content: render_diff(spec.expected, actual), name: "Diff")

        @rendered_message = <<~MSG
          #{template}

          #{environment}

          #{rendered_diff}

          ===========================

          To rerun this spec, run the following command:
            $ #{self.class.rerun_command_for(spec)}
        MSG
      end

      private

      def render_diff(expected, actual)
        SuperDiff::EqualityMatchers::Main.call(expected:, actual:)
      end

      def render_box(name:, content:)
        TTY::Box.frame(content, width: width, title: {top_left: name}).strip
      end
    end
  end
end
