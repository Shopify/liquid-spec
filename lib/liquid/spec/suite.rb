# frozen_string_literal: true

require "yaml"

module Liquid
  module Spec
    # Represents a test suite configuration loaded from suite.yml
    class Suite
      SUITE_FILE = "suite.yml"

      attr_reader :path, :name, :description, :hint, :features, :defaults, :minimum_complexity,
        :default_iteration_seconds

      def initialize(path)
        @path = path
        @config = load_config
        @name = @config["name"] || File.basename(path)
        @description = @config["description"]
        @hint = @config["hint"]
        @features = (@config["features"] || []).map(&:to_sym)
        @defaults = (@config["defaults"] || {}).transform_keys(&:to_sym)
        @minimum_complexity = @config["minimum_complexity"]
        @timings = @config["timings"] || false
        @default_iteration_seconds = @config["default_iteration_seconds"] || 5
      end

      # Whether this suite should collect timing information
      def timings?
        @timings
      end

      # Whether this suite should be included in default runs
      def default?
        @config.fetch("default", true)
      end

      # Check if this suite should be skipped given a set of missing features
      def skipped_by?(missing_features)
        return false if features.empty?

        missing_set = missing_features.is_a?(Set) ? missing_features : Set.new(missing_features.map(&:to_sym))
        features.any? { |f| missing_set.include?(f) }
      end

      # Suite identifier (directory name)
      def id
        @id ||= File.basename(path).to_sym
      end

      class << self
        # Find all suites: the gem's specs directory plus local suites from
        # ./specs/<name>/suite.yml in the invoking project (so implementations
        # can ship their own benchmark/spec suites and select them with -s).
        # LIQUID_SPEC_LOCAL_DIR carries the original working directory across
        # the chdir that `liquid-spec bench` subprocesses perform.
        def all
          @all ||= begin
            dirs = Dir[File.join(SPEC_DIR, "*")]
            local_root = File.join(ENV["LIQUID_SPEC_LOCAL_DIR"] || Dir.pwd, "specs")
            if File.expand_path(local_root) != File.expand_path(SPEC_DIR)
              dirs += Dir[File.join(local_root, "*")]
            end
            dirs.select do |dir|
              File.directory?(dir) && File.exist?(File.join(dir, SUITE_FILE))
            end.map { |dir| new(dir) }
          end
        end

        # Find default suites (included in :all runs)
        def defaults
          all.select(&:default?)
        end

        # Find a suite by name/id
        def find(id)
          id_sym = id.to_sym
          all.find { |s| s.id == id_sym }
        end

        # Clear cached suites (for testing)
        def reset!
          @all = nil
        end
      end

      private

      def load_config
        suite_file = File.join(@path, SUITE_FILE)
        if File.exist?(suite_file)
          YAML.safe_load(File.read(suite_file, encoding: Encoding::UTF_8), permitted_classes: [Symbol]) || {}
        else
          {}
        end
      end
    end

    # Spec directory constant
    SPEC_DIR = File.expand_path("../../../specs", __dir__)
  end
end
