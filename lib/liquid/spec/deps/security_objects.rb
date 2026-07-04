# frozen_string_literal: true

require "liquid"

# Plain (non-Drop) objects that implement #to_liquid in various ways, used to
# verify that the to_liquid protocol gates access to the original object.
# See specs/liquid_ruby/security_drops.yml (to_liquid protocol section).
class ToLiquidHashObject
  def to_liquid; { "name" => "from_to_liquid", "status" => "ok" }; end
end

class ToLiquidStringObject
  def to_liquid; "i_am_a_string"; end
end

class ToLiquidArrayObject
  def to_liquid; [10, 20, 30]; end
end

class ToLiquidNilObject
  def to_liquid; nil; end
end

Liquid::Spec::ClassRegistry.register("ToLiquidHashObject") { |_p| ToLiquidHashObject.new }
Liquid::Spec::ClassRegistry.register("ToLiquidStringObject") { |_p| ToLiquidStringObject.new }
Liquid::Spec::ClassRegistry.register("ToLiquidArrayObject") { |_p| ToLiquidArrayObject.new }
Liquid::Spec::ClassRegistry.register("ToLiquidNilObject") { |_p| ToLiquidNilObject.new }
