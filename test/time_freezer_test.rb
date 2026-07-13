# frozen_string_literal: true

require_relative "test_helper"
require "liquid/spec/time_freezer"

class TimeFreezerTest < Minitest::Test
  def test_spec_clock_is_the_declared_utc_instant
    observed = nil
    observed_tz = nil

    Liquid::Spec::TimeFreezer.freeze_spec_time do
      observed = Time.now
      observed_tz = ENV["TZ"]
    end

    assert_equal Time.utc(2024, 1, 1, 0, 1, 58), observed
    assert_equal "UTC", observed_tz
  end

  def test_current_time_exposes_the_frozen_clock_for_render_registers
    frozen = Time.new(2031, 7, 19, 23, 45, 12, "+09:30")

    Liquid::Spec::TimeFreezer.freeze(frozen) do
      assert_equal frozen, Liquid::Spec::TimeFreezer.current_time
    end
  end

  def test_spec_clock_restores_timezone_and_wall_clock
    original_tz = ENV["TZ"]
    before = Time.now

    Liquid::Spec::TimeFreezer.freeze_spec_time { assert_equal "UTC", ENV["TZ"] }

    original_tz.nil? ? assert_nil(ENV["TZ"]) : assert_equal(original_tz, ENV["TZ"])
    assert_operator Time.now, :>=, before
  end

  def test_freeze_supports_a_different_date_and_positive_offset
    instant = Time.new(2031, 7, 19, 23, 45, 12, "+09:30")

    Liquid::Spec::TimeFreezer.freeze(instant) do
      assert_equal instant, Time.now
      assert_equal "2031-07-19 23:45:12 +0930", Time.now.strftime("%Y-%m-%d %H:%M:%S %z")
    end
  end

  def test_freeze_supports_an_earlier_date_and_negative_offset
    instant = Time.new(1998, 2, 3, 4, 5, 6, "-07:00")

    Liquid::Spec::TimeFreezer.freeze(instant) do
      assert_equal instant, Time.now
      assert_equal "1998-02-03 04:05:06 -0700", Time.now.strftime("%Y-%m-%d %H:%M:%S %z")
    end
  end

  def test_unfrozen_clock_without_timezone_override_tracks_machine_realtime
    original_tz = ENV["TZ"]
    machine_seconds = Process.clock_gettime(Process::CLOCK_REALTIME)
    ruby_seconds = Time.now.to_f

    assert_nil Liquid::Spec::TimeFreezer.frozen_time
    original_tz.nil? ? assert_nil(ENV["TZ"]) : assert_equal(original_tz, ENV["TZ"])
    assert_in_delta machine_seconds, ruby_seconds, 0.25
  end
end
