module Liquid
  module Spec
    class LiquidSource < Source
      private

      def specs
        Dir[File.join(@spec_path, "*")].map do |spec_dir|
          Unit.new(
            name: build_name(spec_dir),
            expected: build_expected(spec_dir),
            template: build_template(spec_dir),
            environment: build_environment(spec_dir),
            filesystem: build_filesystem(spec_dir),
          )
        end
      end

      private

      def build_name(dir)
        File.basename(dir)
      end

      def build_expected(dir)
        filepath = File.join(dir, "expected.html")
        File.read(filepath)
      end

      def build_template(dir)
        filepath = File.join(dir, "template.liquid")
        File.read(filepath)
      end

      def build_environment(dir)
        filepath = File.join(dir, "environment.yml")
        data = File.read(filepath)
        YAML.unsafe_load(data)
      end

      def build_filesystem(dir)
        filepath = File.join(dir, "filesystem")
        return {} unless File.directory?(filepath)
        raise "Implement filesystem"
      end
    end
  end
end
