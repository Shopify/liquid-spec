# frozen_string_literal: true

require "timecop"
require_relative "failure_message"
require "digest"

module Liquid
  module Spec
    class TestGenerator
      include Enumerable

      class << self
        def define_on(klass, sources: Liquid::Spec.all_sources, &block)
          blk = block.nil? ? ->(spec) { assert_parity_for_spec(spec) } : block
          new(klass, sources).define_on(klass, &blk)
        end
      end
      def initialize(klass, sources)
        @klass = klass
        @sources = sources
      end

      def each_group(&block)
        mapped = sort_by(&:name)

        mapped.map! do |spec|
          klass, test_name = spec.name.split("#", 2)

          if test_name.nil?
            test_name = klass
            klass = "MiscTest"
          end

          [klass, [test_name, spec]]
        end

        mapped.group_by(&:first).each do |k, val|
          items = val.map(&:last).map do |test_name, spec|
            slug_name = test_name.gsub(/\s+/, "_").downcase
            slug_name = slug_name.start_with?("test_") ? slug_name : "test_#{slug_name}"
            slug_name.delete_suffix!("_")
            spec.name = slug_name
            spec
          end

          uniq = items.uniq(&:name).sort_by(&:name)

          if uniq.size != items.size
            duplicated = items.group_by(&:name).select { |_, v| v.size > 1 }.map(&:first)
            raise "duplicate test names: #{duplicated}"
          end

          block.call(k, uniq)
        end
      end

      def define_on(klass, &block)
        base = @klass

        each_group do |klass_name, specs|
          klass = Class.new(base)
          klass.define_singleton_method(:name) { klass_name }
          klass.const_set(klass_name, klass)

          specs.each do |spec|
            klass.define_method(spec.name) do
              instance_exec(spec, &block)
            end
          end
        end
      end

      def each(&block)
        return enum_for(__method__) unless block_given?

        @sources.each do |source|
          source.each(&block)
        end
      end
    end
  end
end
