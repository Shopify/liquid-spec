# frozen_string_literal: true

module Liquid
  module Spec
    class LiquidSource < Source
      # Global hint for all specs in this source directory
      def hint
        metadata["hint"]
      end

      # Required options that adapters must support to run these specs
      def required_options
        @required_options ||= (metadata["required_options"] || {}).transform_keys(&:to_sym)
      end

      private

      def metadata
        @metadata ||= begin
          # Look for _metadata.yml in the spec directory
          metadata_path = File.join(@spec_path, "_metadata.yml")
          if File.exist?(metadata_path)
            YAML.safe_load_file(metadata_path) || {}
          else
            {}
          end
        end
      end

      def specs
        Dir[File.join(@spec_path, "*")].reject do |p|
          File.basename(p).start_with?("_") || File.basename(p) == "suite.yml"
        end.select { |p| File.directory?(p) }.map do |spec_dir|
          Unit.new(
            name: build_name(spec_dir),
            expected: build_expected(spec_dir),
            template: build_template(spec_dir),
            environment: build_environment(spec_dir),
            filesystem: build_filesystem(spec_dir),
            source_hint: effective_hint,
            source_required_options: effective_defaults,
          )
        end
      end

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
