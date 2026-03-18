# frozen_string_literal: true

# YAML coders for liquid-spec capture pipeline.
#
# Defines encode_with on Ruby test objects so YAML.dump produces portable
# instantiate: format instead of !ruby/object: tags. This eliminates the
# need for post-processing captured YAML.
#
# Usage: require this file in any context that YAML.dump's test objects
# (shopify_liquid_patch.rb, standard_filter_patch.rb, helpers.rb).

require "yaml"

# --- Core type coders ---

# Range serializes as instantiate:Range: [begin, end]
class Range
  def encode_with(coder)
    coder.represent_map(nil, { "instantiate:Range:" => [self.begin, self.end] })
  end
end

# Liquid::Drop class object serializes as instantiate:LiquidDropClass: {}
class << Liquid::Drop
  def encode_with(coder)
    coder.represent_map(nil, { "instantiate:LiquidDropClass:" => {} })
  end
end

# --- Generic fallback for any Liquid::Drop subclass ---
# If a Drop subclass doesn't define encode_with, serialize its ivars
# using the class's short name as the registry name.
class Liquid::Drop
  def encode_with(coder)
    params = {}
    instance_variables.each do |ivar|
      next if ivar == :@context

      params[ivar.to_s.delete_prefix("@")] = instance_variable_get(ivar)
    end
    name = self.class.name&.split("::")&.last || self.class.to_s
    coder.represent_map(nil, { "instantiate:#{name}:" => params })
  end
end

# --- Helper to register custom encode_with on specific classes ---

module LiquidSpecYAMLCoder
  def self.register(klass, registry_name, skip_ivars: [:@context], ivar_map: {})
    klass.define_method(:encode_with) do |coder|
      params = {}
      instance_variables.each do |ivar|
        next if skip_ivars.include?(ivar)

        key = ivar_map[ivar] || ivar.to_s.delete_prefix("@")
        params[key] = instance_variable_get(ivar)
      end
      coder.represent_map(nil, { "instantiate:#{registry_name}:" => params })
    end
  end

  def self.register_empty(klass, registry_name)
    klass.define_method(:encode_with) do |coder|
      coder.represent_map(nil, { "instantiate:#{registry_name}:" => {} })
    end
  end

  def self.register_hash(klass, registry_name)
    klass.define_method(:encode_with) do |coder|
      coder.represent_map(nil, { "instantiate:#{registry_name}:" => Hash[self] })
    end
  end
end
