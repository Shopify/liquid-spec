module Liquid
  module Spec
    Unit = Struct.new(
      :name,
      :expected,
      :template,
      :environment,
      :filesystem,
      keyword_init: true
    )
  end
end
