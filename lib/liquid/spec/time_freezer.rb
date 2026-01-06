# frozen_string_literal: true

module Liquid
  module Spec
    # Simple Time.now freezer - replaces Timecop dependency
    module TimeFreezer
      class << self
        def freeze(time)
          @frozen_time = time
          Time.singleton_class.prepend(FrozenTime) unless @prepended
          @prepended = true
          yield
        ensure
          @frozen_time = nil
        end

        def frozen_time
          @frozen_time
        end
      end

      module FrozenTime
        def now
          Liquid::Spec::TimeFreezer.frozen_time || super
        end
      end
    end
  end
end
