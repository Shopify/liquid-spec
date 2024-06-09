require "tty-box"

module Liquid
  module Spec
    class FailureMessage
      attr_reader :spec, :actual, :width

      def initialize(spec, actual, width: nil, exception: nil)
        @spec = spec
        @actual = actual
        @width = width
        @exception = exception
      end

      class << self
        def rerun_command_for(spec)
          slugified_name = spec.name.gsub(/\s+/, "_")
          if defined?(TLDR)
            "bundle exec tldr test/integration/liquid_spec.rb --name=/#{slugified_name}/"
          else
            "rake liquid_spec TESTOPTS=\"--name=/#{slugified_name}/\""
          end
        end
      end

      def to_s
        return @rendered_message if defined?(@rendered_message)

        sections = []

        sections << render_box(content: spec.template, name: "Template")
        sections << render_box(content: spec.environment.inspect, name: "Environment")

        if @exception
          exception_info_with_backtrace = <<~INFO
            #{@exception.message}

            #{filtered_backtrace.join("\n")}
          INFO

          sections << render_box(content: exception_info_with_backtrace, name: "🚨 Got error: #{@exception.class}", padding: 1)
        else
          sections << render_box(content: render_diff(spec.expected, actual), name: "Diff")
        end

        @rendered_message = <<~MSG
          #{sections.join("\n\n")}

          ===========================

          To rerun this spec, run the following command:
            $ #{self.class.rerun_command_for(spec)}
        MSG
      end

      private

      def render_diff(expected, actual)
        SuperDiff::Basic::Differs::MultilineString.call(expected, actual, indent_level: 0)
      end

      def render_box(name:, content:, padding: 0)
        header = "━━━━━━━ #{name} ━━━━━━━"
        trailer = "━" * header.length

        <<~BOX
          #{header}
          #{content}
          #{trailer}
        BOX
      end

      def filtered_backtrace
        @filtered_backtrace ||= begin
          if defined?(TLDR)
            TLDR.filter_backtrace(@exception.backtrace)
          else
            backtrace
          end
        end
      end
    end
  end
end
