# frozen_string_literal: true

require "test_helper"

# Covers RobotLab::Web.run — the entry point both web routes wrap — including
# the :delta token-streaming layer, with a fake streaming robot (no LLM).
class RobotLab::Web::TestRun < Minitest::Test
  RunCtx  = Struct.new(:request, :response, :error, :robot, keyword_init: true)
  Result  = Struct.new(:reply)
  Chunk   = Struct.new(:content)

  class StreamingRobot
    attr_reader :name

    def initialize(name = "streamer") = @name = name

    def run(message, hooks:, &stream)
      hook = hooks.first
      ctx = RunCtx.new(request: message, robot: self)
      hook.before_run(ctx)
      %w[Hel lo!].each { |frag| stream&.call(Chunk.new(frag)) }
      stream&.call(Chunk.new(nil))   # empty/role-only chunk — must be skipped
      ctx.response = Result.new("Hello!")
      hook.after_run(ctx)
      ctx.response
    end
  end

  def roles(events) = events.map(&:role)

  def test_run_emits_user_deltas_then_robot_in_order
    events = []
    result = RobotLab::Web.run(StreamingRobot.new, "hi") { |e| events << e }

    assert_equal "Hello!", result.reply
    assert_equal %i[user delta delta robot], roles(events)
  end

  def test_deltas_carry_fragments_and_skip_empty_chunks
    events = []
    RobotLab::Web.run(StreamingRobot.new, "hi") { |e| events << e }

    deltas = events.select { |e| e.role == :delta }
    assert_equal %w[Hel lo!], deltas.map(&:content)
    assert_equal "streamer", deltas.first.robot_name
  end

  def test_final_robot_event_has_full_reply
    events = []
    RobotLab::Web.run(StreamingRobot.new, "hi") { |e| events << e }

    assert_equal "Hello!", events.last.text
  end

  def test_deltas_are_not_written_to_activity_log
    RobotLab::Web::ActivityLog.clear
    RobotLab::Web.run(StreamingRobot.new, "hi") { |_e| }
    refute_includes RobotLab::Web::ActivityLog.recent(50).map { |e| e[:type] }, :delta
  end
end
