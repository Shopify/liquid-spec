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
            # Return placeholder for circular references to prevent JSON nesting errors
            return "[circular]" if seen.key?(obj)

            case obj
            when nil, true, false, Integer
              obj
            when Float
              # Handle special float values that JSON can't encode
              if obj.nan? || obj.infinite?
                nil
              else
                obj
              end
            when Symbol
              obj.to_s
            when String
              # Ensure valid UTF-8 for JSON encoding
              sanitize_string(obj)
            when Hash
              wrapped = {}
              seen[obj] = wrapped
              obj.each do |k, v|
                # Sanitize keys for JSON (symbols -> strings, binary -> utf8)
                key = case k
                      when Symbol then k.to_s
                      when String then sanitize_string(k)
                      else k.to_s
                      end
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

          # Convert string to valid UTF-8 for JSON encoding
          # Binary data gets replacement characters
          def sanitize_string(str)
            return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

            str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
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
          # Some methods (to_s, to_liquid_value, to_number) must be called directly,
          # not via [] which is for property access
          DIRECT_METHODS = %w[to_s to_liquid to_liquid_value to_number size length first last blank?].to_set.freeze

          def access_drop(drop, property)
            # Call certain methods directly - they're not properties
            if DIRECT_METHODS.include?(property) && drop.respond_to?(property)
              drop.public_send(property)
            elsif drop.respond_to?(:[])
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
