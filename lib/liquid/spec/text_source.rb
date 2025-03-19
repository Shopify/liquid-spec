# frozen_string_literal: true

module Liquid
  module Spec
    class TextSource < Source
      private

      def specs
        @specs ||= TextSourceParser.new(lines)
      end

      def lines
        spec_data.lines
      end
    end

    class TextSourceParser
      include Enumerable

      class State
        def initialize(lines)
          @lines = lines
        end

        private

        def peek
          lines.first
        end

        def expect_match(pattern)
          if lines.first.match(pattern)
            lines.shift
          else
            raise(<<~ERROR)
              Expected line to match #{pattern}
              Line:
                #{lines.first}
            ERROR
          end
        end

        attr_reader :lines
      end

      class Name < State
        def next(data)
          expect_match(/===+/)
          data["name"] = lines.shift.chomp.gsub(/\s+/, "_")
          expect_match(/===+/)

          Environment.new(lines)
        end
      end

      class Environment < State
        def next(data)
          yaml = +"---\n"

          loop do
            break if peek.match(/___+/) || peek.match(/---+/)

            yaml << lines.shift
          end

          data["environment"] = YAML.unsafe_load(yaml)

          klass = if peek.match(/___+/)
            Filesystem
          else
            Template
          end

          klass.new(lines)
        end
      end

      class Filesystem < State
        def next(data)
          expect_match(/___+/)

          yaml = +"---\n"

          loop do
            break if peek.match(/---+/)

            yaml << lines.shift
          end

          data["filesystem"] = YAML.unsafe_load(yaml)

          Template.new(lines)
        end
      end

      class Template < State
        def next(data)
          expect_match(/---+/)
          template = +""

          loop do
            break if peek.match(/\+\+\++/)

            template << lines.shift
          end

          data["template"] = template.strip

          Expected.new(lines)
        end
      end

      class Expected < State
        def next(data)
          expect_match(/\+\+\++/)
          expected = +""

          loop do
            break if peek.nil? || peek.match(/===+/)

            expected << lines.shift
          end

          data["expected"] = expected.chomp("")

          return Finished.new(lines) if peek.nil?

          Name.new(lines)
        end
      end

      class Finished < State
        def next(data)
          raise NotImplementedError, "Text source reached EOF"
        end
      end

      def initialize(lines)
        @state = Name.new(lines)
      end

      def each(&block)
        loop do
          break if @state.is_a?(Finished)

          unit = _next
          break if unit.nil?

          block.call(unit)
        end
      end

      private

      def _next
        unit_data = {}

        loop do
          @state = @state.next(unit_data)
          break if @state.is_a?(Name) || @state.is_a?(Finished)
        end

        Unit.new(
          name: unit_data["name"],
          expected: unit_data["expected"],
          template: unit_data["template"],
          environment: unit_data["environment"],
          filesystem: unit_data["filesystem"],
          context_klass: Liquid::Context,
        )
      end
    end
  end
end
