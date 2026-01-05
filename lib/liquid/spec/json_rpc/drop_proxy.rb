# frozen_string_literal: true

module Liquid
  module Spec
    module JsonRpc
      # Registry for tracking drops that need RPC callbacks
      class DropRegistry
        def initialize
          @drops = {}
          @next_id = 0
        end

        # Register a drop and return its ID
        def register(drop)
          id = "drop_#{@next_id += 1}"
          @drops[id] = drop
          id
        end

        # Look up a drop by ID
        def [](id)
          @drops[id]
        end

        # Clear all registered drops (between specs)
        def clear
          @drops.clear
          @next_id = 0
        end

        # Number of registered drops
        def size
          @drops.size
        end
      end

      # Utilities for wrapping/unwrapping drops for JSON-RPC transport
      module DropProxy
        RPC_DROP_KEY = "_rpc_drop"

        class << self
          # Wrap an object for JSON transport
          # Drops become { "_rpc_drop": "id", "type": "ClassName" }
          # Primitives pass through unchanged
          # Hashes and arrays are recursively wrapped
          def wrap(obj, registry, seen = {}.compare_by_identity)
            return seen[obj] if seen.key?(obj)

            case obj
            when nil, true, false, Integer, Float, String, Symbol
              # Primitives pass through
              obj.is_a?(Symbol) ? obj.to_s : obj
            when Hash
              wrapped = {}
              seen[obj] = wrapped
              obj.each do |k, v|
                key = k.is_a?(Symbol) ? k.to_s : k
                wrapped[key] = wrap(v, registry, seen)
              end
              wrapped
            when Array
              wrapped = []
              seen[obj] = wrapped
              obj.each { |v| wrapped << wrap(v, registry, seen) }
              wrapped
            when Range
              # Convert ranges to array for JSON
              obj.to_a
            else
              # Check if it's a drop or liquid-compatible object
              if drop_like?(obj)
                drop_id = registry.register(obj)
                { RPC_DROP_KEY => drop_id, "type" => obj.class.name }
              else
                # Try to convert to something JSON-safe
                obj.respond_to?(:to_h) ? wrap(obj.to_h, registry, seen) : obj.to_s
              end
            end
          end

          # Check if an object needs RPC callbacks (is a drop)
          def drop_like?(obj)
            return false if primitive?(obj)

            # Check for Liquid::Drop
            return true if defined?(Liquid::Drop) && obj.is_a?(Liquid::Drop)

            # Check for to_liquid method (custom drops)
            return true if obj.respond_to?(:to_liquid) && !obj.is_a?(String) && !obj.is_a?(Numeric)

            # Check for [] method that's not a Hash/Array (drop-like access)
            return true if obj.respond_to?(:[]) && !obj.is_a?(Hash) && !obj.is_a?(Array) && !obj.is_a?(String)

            false
          end

          # Check if object is a JSON primitive
          def primitive?(obj)
            case obj
            when nil, true, false, Integer, Float, String, Symbol
              true
            else
              false
            end
          end

          # Check if a value is an RPC drop marker
          def rpc_drop?(value)
            value.is_a?(Hash) && value.key?(RPC_DROP_KEY)
          end

          # Extract drop ID from RPC marker
          def drop_id(value)
            value[RPC_DROP_KEY] if rpc_drop?(value)
          end

          # Access a property on a drop
          def access_drop(drop, property)
            if drop.respond_to?(:[])
              drop[property]
            elsif drop.respond_to?(property)
              drop.public_send(property)
            else
              nil
            end
          end

          # Call a method on a drop with arguments
          def call_drop(drop, method_name, args)
            if drop.respond_to?(method_name)
              drop.public_send(method_name, *args)
            else
              raise DropAccessError, "Method #{method_name} not found on #{drop.class}"
            end
          end

          # Iterate a drop (for {% for %} loops)
          def iterate_drop(drop)
            if drop.respond_to?(:to_a)
              drop.to_a
            elsif drop.respond_to?(:each)
              drop.each.to_a
            else
              [drop]
            end
          end
        end
      end

      # Error accessing a drop property
      class DropAccessError < StandardError; end
    end
  end
end
