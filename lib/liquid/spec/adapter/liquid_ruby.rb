module Liquid
  module Spec
    module Adapter
      class LiquidRuby
        def render(spec)
          if filesystem = spec["filesystem"]
            Liquid::Template.file_system = filesystem
          end
          template = Liquid::Template.parse(spec["template"])
          template.render(spec["environment"])
        end
      end
    end
  end
end
