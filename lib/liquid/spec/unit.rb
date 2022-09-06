module Liquid
  module Spec
    Unit = Struct.new(
      :name,
      :expected,
      :template,
      :environment,
      :filesystem,
      :error_mode,
      keyword_init: true
    )
  end
end
