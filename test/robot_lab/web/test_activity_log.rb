# frozen_string_literal: true

require "test_helper"

class RobotLab::Web::TestActivityLog < Minitest::Test
  Log = RobotLab::Web::ActivityLog

  def setup
    Log.clear
  end

  def test_logs_and_returns_recent_newest_first
    Log.log(:robot, name: "a")
    Log.log(:tool_call, name: "b")
    recent = Log.recent(10)
    assert_equal :tool_call, recent.first[:type]
    assert_equal :robot, recent.last[:type]
  end

  def test_recent_respects_limit
    5.times { |i| Log.log(:robot, n: i) }
    assert_equal 2, Log.recent(2).size
  end

  def test_bounded_to_max_events
    (Log::MAX_EVENTS + 20).times { Log.log(:robot) }
    assert_equal Log::MAX_EVENTS, Log.recent(1000).size
  end

  def test_safe_log_swallows_errors
    # A non-symbolizable type would raise inside log; safe_log must not.
    assert_nil Log.safe_log(Object.new.tap { |o| def o.to_sym = raise("nope") })
  end
end
