# frozen_string_literal: true

require "super_diff"
require "pp"
require "tty-box"

module Liquid
  module Spec
    class FailureMessage
      attr_reader :spec, :actual, :width

      def initialize(spec, actual, width: nil, exception: nil, run_command: nil, test_name: nil, context: nil)
        @spec = spec
        @actual = actual
        @width = width
        @exception = exception
        @run_command = run_command || "dev test test/integration/liquid_spec.rb"
        @test_name = test_name
        @context = context
        @pastel = Pastel.new
      end

      def to_s
        return @rendered_message if defined?(@rendered_message)

        sections = []

        sections << render_kv(content: spec.template, name: "Template")
        sections << render_kv(content: environment_or_context_environments.pretty_inspect, name: "Environment")
        unless spec.filesystem.empty?
          sections << render_kv(content: spec.filesystem.pretty_inspect, name: "Filesystem")
        end
        config = {
          error_mode: spec.error_mode,
          context_klass: spec.context&.class || spec.context_klass,
          template_factory: spec.template_factory&.class,
          render_errors: spec.render_errors,
        }.map { |k, v| "#{k}: #{v.nil? ? @pastel.dim(v.inspect) : @pastel.bold.blue(v)}" }.join("\n")
        sections << render_kv(content: config, name: "Config")
        sections << render_kv(content: spec.message, name: "Message") if spec.message
        sections << render_kv(content: rerun_command, name: "Rerun command")
        @context&.exception_renderer&.rendered_exceptions&.each_with_index do |exception, i|
          sections << render_exception(exception, title: "Handled exception #{i}", color: :yellow, border: nil)
        end

        info = render_box(content: sections.join("\n"), name: nil, border: :light)

        main = if @exception
          render_exception(@exception, title: @pastel.bold("Render error"))
        else
          render_box(content: render_diff(spec.expected, actual), name: @pastel.bold("Diff"))
        end

        @rendered_message = "#{info}\n#{main}"
      end

      private

      def render_exception(exception, title:, color: :red, border: :light)
        err = exception.is_a?(Liquid::InternalError) ? exception.cause : exception

        exception_info = <<~INFO
          #{@pastel.bold(err.class)}: #{err.message}
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
        SuperDiff::Basic::Differs::MultilineString.call(expected, actual, indent_level: 0)
      end

      def render_box(name:, content:, padding: [0, 1], bottom_right: nil, color: :cyan, border: :light)
        if name
          name = @pastel.send(color, name)
          name = " #{name} "
        end
        bottom_right = @pastel.bold(bottom_right) if bottom_right
        bottom_right = " #{bottom_right} " if bottom_right
        TTY::Box.frame(content, padding: padding, align: :left, title: { top_left: name, bottom_right: }, border:)
      end

      def filter_backtrace(exception)
        if defined?(Minitest)
          Minitest.filter_backtrace(exception.backtrace)
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
