# frozen_string_literal: true

require "yaml"

module Liquid
  module Spec
    # Represents a test suite configuration loaded from suite.yml
    class Suite
      SUITE_FILE = "suite.yml"

      attr_reader :path, :name, :description, :hint, :required_features, :defaults, :minimum_complexity

      def initialize(path)
        @path = path
        @config = load_config
        @name = @config["name"] || File.basename(path)
        @description = @config["description"]
        @hint = @config["hint"]
        @required_features = (@config["required_features"] || []).map(&:to_sym)
        @defaults = (@config["defaults"] || {}).transform_keys(&:to_sym)
        @minimum_complexity = @config["minimum_complexity"]
      end

      # Whether this suite should be included in default runs
      def default?
        @config.fetch("default", true)
      end

      # Check if this suite can run with the given features
      def runnable_with?(features)
        return true if required_features.empty?

        features_set = features.map(&:to_sym).to_set
        required_features.all? { |f| features_set.include?(f) }
      end

      # List of missing features
      def missing_features(features)
        features_set = features.map(&:to_sym).to_set
        required_features.reject { |f| features_set.include?(f) }
      end

      # Suite identifier (directory name)
      def id
        @id ||= File.basename(path).to_sym
      end

      class << self
        # Find all suites in the specs directory
        def all
          @all ||= Dir[File.join(SPEC_DIR, "*")].select do |dir|
            File.directory?(dir) && File.exist?(File.join(dir, SUITE_FILE))
          end.map { |dir| new(dir) }
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
          YAML.safe_load_file(suite_file, permitted_classes: [Symbol]) || {}
        else
          {}
        end
      end
    end

    # Spec directory constant
    SPEC_DIR = File.expand_path("../../../specs", __dir__)
  end
end
