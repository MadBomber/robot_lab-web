# frozen_string_literal: true

require "test_helper"

# Drive StreamHook's class methods directly with fake hook contexts so the
# event-production logic is tested in isolation — no LLM, no real robot run.
class RobotLab::Web::TestStreamHook < Minitest::Test
  Hook = RobotLab::Web::StreamHook
  Sink = RobotLab::Web::EventSink

  FakeRobot  = Struct.new(:name)
  FakeResult = Struct.new(:reply)

  # Minimal stand-ins for the run / tool_call hook contexts.
  RunCtx = Struct.new(:request, :response, :error, :robot, keyword_init: true)
  ToolCtx = Struct.new(:tool_name, :tool_args, :tool_result, :tool_error, :robot, keyword_init: true)

  def capture(&)
    events = []
    Sink.capture(->(e) { events << e }, &)
    events
  end

  def robot
    FakeRobot.new("support")
  end

  def test_before_run_emits_user_event
    events = capture { Hook.before_run(RunCtx.new(request: "hello", robot: robot)) }
    assert_equal 1, events.size
    assert_equal :user, events.first.role
    assert_equal "hello", events.first.text
    assert_equal "support", events.first.robot_name
  end

  def test_after_run_emits_robot_reply
    ctx = RunCtx.new(response: FakeResult.new("the answer"), robot: robot)
    events = capture { Hook.after_run(ctx) }
    assert_equal :robot, events.first.role
    assert_equal "the answer", events.first.text
  end

  def test_after_run_with_error_emits_error_event
    ctx = RunCtx.new(error: RuntimeError.new("kaboom"), robot: robot)
    events = capture { Hook.after_run(ctx) }
    assert_equal :error, events.first.role
    assert_equal "kaboom", events.first.error_message
  end

  def test_tool_call_events
    before = capture do
      Hook.before_tool_call(ToolCtx.new(tool_name: "lookup", tool_args: { id: 1 }, robot: robot))
    end
    assert_equal :tool_call, before.first.role
    assert_equal "lookup", before.first.tool_name

    after = capture do
      Hook.after_tool_call(ToolCtx.new(tool_name: "lookup", tool_result: "found", robot: robot))
    end
    assert_equal :tool_result, after.first.role
    assert_equal "found", after.first.content[:result]
  end

  def test_after_tool_call_with_error
    ctx = ToolCtx.new(tool_name: "lookup", tool_error: RuntimeError.new("no rows"), robot: robot)
    events = capture { Hook.after_tool_call(ctx) }
    assert_equal "no rows", events.first.content[:error]
  end
end
