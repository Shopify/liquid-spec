# frozen_string_literal: true

require "super_diff"
require "pp"

module Liquid
  module Spec
    class FailureMessage
      attr_reader :spec, :actual, :width

      def self.color_enabled?
        !ENV["NO_COLOR"]
      end

      SuperDiff.configure do |config|
        config.color_enabled = color_enabled?
      end

      def initialize(spec, actual, width: nil, exception: nil, run_command: nil, test_name: nil, context: nil, message: nil)
        @pastel = Pastel.new(enabled: self.class.color_enabled?)
        @spec = spec
        @actual = actual
        @width = width
        @exception = exception
        @run_command = run_command || "dev test test/integration/liquid_spec.rb"
        @message = @pastel.bold.red(message || "template did not render as expected")
        @test_name = test_name
        @context = context
      end

      def to_s
        return @rendered_message if defined?(@rendered_message)

        sections = []
        sections << render_kv(content: spec.template, name: "Template")
        sections << render_kv(content: environment_or_context_environments.pretty_inspect, name: "Environment")
        sections << render_filesystem(spec.filesystem)
        config = {
          error_mode: spec.error_mode,
          context_klass: spec.context&.class || spec.context_klass,
          template_factory: spec.template_factory&.class,
          render_errors: spec.render_errors,
        }.map { |k, v| "#{k}: #{v.nil? ? @pastel.dim(v.inspect) : @pastel.bold.blue(v)}" }.join("\n")
        sections << render_kv(content: config, name: "Config")
        sections << render_kv(content: spec.message, name: "Message") if spec.message
        effective_hint = spec.respond_to?(:effective_hint) ? spec.effective_hint : spec.hint
        sections << render_kv(content: effective_hint, name: "Hint", color: :yellow) if effective_hint
        sections << render_kv(content: rerun_command, name: "Rerun command")
        @context&.exception_renderer&.rendered_exceptions&.each_with_index do |exception, i|
          sections << render_exception(exception, title: "Handled exception #{i}", color: :yellow, border: nil)
        end

        info = render_box(content: sections.join("\n"), name: @message, border: :light)

        main = if @exception
          render_exception(@exception, title: @pastel.bold("Render error"))
        else
          render_box(content: render_diff(spec.expected, actual), name: @pastel.bold("Diff"))
        end

        @rendered_message = "#{info}\n#{main}"
      rescue StandardError => e
        @rendered_message = "Error rendering failure message: #{e.message}\n#{e.backtrace.join("\n")}\n\n#{pretty_inspect}"
      end

      private

      def render_filesystem(filesystem)
        return unless filesystem
        return if filesystem.respond_to?(:empty?) && filesystem.empty?

        render_kv(content: filesystem.pretty_inspect, name: "Filesystem")
      end

      def render_exception(exception, title:, color: :red, border: :light)
        err = exception.is_a?(Liquid::InternalError) ? exception.cause : exception
        first_few_lines = @pastel.dim(filter_backtrace(err).first(5).map { |line| @pastel.dim("  #{line}") }.join("\n"))

        exception_info = <<~INFO
          #{@pastel.bold(err.class)}: #{err.message}
          #{first_few_lines}
        INFO

        bottom_right = exception.is_a?(Liquid::InternalError) ? "caused by #{exception.class}" : nil

        if border.nil?
          bottom_right = bottom_right ? @pastel.dim("(" + bottom_right + ")") : nil
          title = @pastel.bold.send(color, title)
          "#{title}\n#{exception_info}\n#{@pastel.dim(bottom_right)}"
        else
          render_box(content: exception_info, name: title, bottom_right:, color:)
        end
      end

      def render_kv(content:, name:, color: :cyan)
        name = @pastel.bold.send(color, name)
        name = name.to_s
        value = content.is_a?(String) ? content + "\n" : content.pretty_inspect
        "#{name}\n#{value.strip}\n"
      end

      def render_diff(expected, actual)
        SuperDiff::Basic::Differs::MultilineString.call(expected || "(no expected value given)", actual || "", indent_level: 0)
      end

      def render_box(name:, content:, padding: [0, 1], bottom_right: nil, color: :cyan, border: :light)
        title = name ? @pastel.send(color, name) : nil
        footer = bottom_right ? @pastel.bold(bottom_right) : nil

        lines = content.lines.map(&:chomp)
        content_width = lines.map { |l| strip_ansi(l).length }.max || 0
        title_width = title ? strip_ansi(title).length + 4 : 0
        footer_width = footer ? strip_ansi(footer).length + 4 : 0
        box_width = [content_width + 4, title_width + 4, footer_width + 4].max

        top = if title
          "┌─ #{title} " + "─" * [0, box_width - strip_ansi(title).length - 5].max + "┐"
        else
          "┌" + "─" * (box_width - 2) + "┐"
        end

        middle = lines.map do |line|
          visible_len = strip_ansi(line).length
          pad = " " * [0, box_width - visible_len - 4].max
          "│ #{line}#{pad} │"
        end.join("\n")

        bottom = if footer
          "└" + "─" * [0, box_width - strip_ansi(footer).length - 5].max + " #{footer} ─┘"
        else
          "└" + "─" * (box_width - 2) + "┘"
        end

        "#{top}\n#{middle}\n#{bottom}"
      end

      def strip_ansi(str)
        str.gsub(/\e\[[0-9;]*m/, "")
      end

      def filter_backtrace(exception)
        if defined?(Minitest)
          Minitest.filter_backtrace(exception.backtrace || [])
        else
          @exception.backtrace
        end
      end

      def rerun_command
        slugified_name = Regexp.escape(@test_name)

        name = if (hex = slugified_name.match(/([0-9a-f]{32})/))
          hex[1]
        else
          slugified_name
        end

        "#{@run_command} --name=/#{name}/"
      end

      def environment_or_context_environments
        if spec.context
          spec.context.static_environments
        else
          spec.environment
        end
      end
    end
  end
end
