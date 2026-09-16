# frozen_string_literal: true

require "set"

module Liquid
  module Spec
    module FeatureCoverage
      REFERENCE_ADAPTER_PATHS = %w[examples/*.rb ci/*.rb].freeze

      Result = Struct.new(:known_orphans, :new_orphans, :stale_baseline) do
        def success?
          new_orphans.empty? && stale_baseline.empty?
        end
      end

      module_function

      def reference_adapter_paths(base)
        REFERENCE_ADAPTER_PATHS.flat_map { |glob| Dir.glob(File.join(base, glob)) }.sort
      end

      def check(spec_tags:, adapter_missing:, baseline:)
        orphans = Set.new(spec_tags)
        orphans.delete_if do |tag|
          adapter_missing.any? { |_, missing| !missing.include?(tag) }
        end
        baseline = Set.new(baseline)

        Result.new(
          (orphans & baseline).sort,
          (orphans - baseline).sort,
          (baseline - orphans).sort,
        )
      end

      def load_baseline(path)
        raise ArgumentError, "Feature coverage baseline is missing: #{path}" unless File.file?(path)

        entries = File.readlines(path, chomp: true).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
        duplicates = entries.tally.select { |_, count| count > 1 }.keys
        unless duplicates.empty?
          raise ArgumentError, "Feature coverage baseline has duplicate entries: #{duplicates.sort.join(', ')}"
        end

        entries.map(&:to_sym).to_set
      end
    end
  end
end
