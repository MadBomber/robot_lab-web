# frozen_string_literal: true

require "test_helper"

class RobotLab::Web::TestEventSink < Minitest::Test
  Sink = RobotLab::Web::EventSink
  Event = RobotLab::Web::Event

  def test_no_current_sink_by_default
    assert_nil Sink.current
  end

  def test_capture_installs_and_restores_sink
    collected = []
    Sink.capture(->(e) { collected << e }) do
      refute_nil Sink.current
      Sink.emit(Event.new(role: :user, content: "hi"))
    end
    assert_nil Sink.current, "sink should be restored after the block"
    assert_equal 1, collected.size
  end

  def test_emit_without_sink_is_a_noop
    assert_nil Sink.emit(Event.new(role: :user, content: "hi"))
  end

  def test_emit_swallows_sink_errors
    Sink.capture(->(_e) { raise "broken consumer" }) do
      assert_nil Sink.emit(Event.new(role: :robot, content: "x"))
    end
  end

  def test_capture_restores_even_on_raise
    Sink.capture(->(_e) {}) do
      assert_raises(RuntimeError) { Sink.capture(->(_e) {}) { raise "boom" } }
    end
    # outer sink still active inside, then restored to nil after
  ensure
    assert_nil Sink.current
  end
end
