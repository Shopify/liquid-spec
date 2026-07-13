# frozen_string_literal: true

module Liquid
  module Spec
    # Simple Time.now freezer - replaces Timecop dependency
    module TimeFreezer
      SPEC_TIME = Time.utc(2024, 1, 1, 0, 1, 58).freeze
      SPEC_TIMEZONE = "UTC"

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

        # The host clock delivered to filters and drops through render registers.
        # It is deliberately not an assign, so templates cannot read it directly.
        def current_time
          frozen_time || Time.now
        end

        # Run a spec-facing operation under liquid-spec's canonical clock.
        # Every execution surface must use this helper so date specs test the
        # timestamp they declare instead of merely comparing wall-clock output.
        def freeze_spec_time
          original_tz = ENV["TZ"]
          ENV["TZ"] = SPEC_TIMEZONE
          freeze(SPEC_TIME) { yield }
        ensure
          ENV["TZ"] = original_tz
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
