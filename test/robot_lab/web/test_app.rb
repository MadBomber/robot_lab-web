# frozen_string_literal: true

require "test_helper"
require "robot_lab/web/app"
require "rack/test"

# Exercises the HTTP surface: dashboard, 404s, CSRF enforcement, and the SSE
# stream framing. A fake robot stands in for a real one — its #run drives the
# StreamHook lifecycle the way robot_lab would, so no LLM is involved.
class RobotLab::Web::TestApp < Minitest::Test
  include Rack::Test::Methods

  RunCtx  = Struct.new(:request, :response, :error, :robot, keyword_init: true)
  ToolCtx = Struct.new(:tool_name, :tool_args, :tool_result, :tool_error, :robot, keyword_init: true)
  FakeResult = Struct.new(:reply)

  Chunk = Struct.new(:content)

  # Simulates robot_lab's Robot#run: invokes the supplied hook for each
  # lifecycle moment against the thread-local sink, and streams the reply in
  # two content chunks the way RubyLLM would.
  class FakeRobot
    attr_reader :name

    def initialize(name) = @name = name

    def run(message, hooks:, &stream)
      hook = hooks.first
      ctx = RunCtx.new(request: message, robot: self)
      hook.before_run(ctx)
      hook.before_tool_call(ToolCtx.new(tool_name: "echo", tool_args: { text: message }, robot: self))
      hook.after_tool_call(ToolCtx.new(tool_name: "echo", tool_result: message, robot: self))
      if stream
        stream.call(Chunk.new("reply: "))
        stream.call(Chunk.new(message))
      end
      ctx.response = FakeResult.new("reply: #{message}")
      hook.after_run(ctx)
      ctx.response
    end
  end

  def app = RobotLab::Web::App

  def setup
    RobotLab::Web::Registry.clear
    RobotLab::Web::Registry.register(FakeRobot.new("echo"))
  end

  def test_dashboard_lists_registered_robots
    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "echo"
  end

  def test_unknown_robot_is_404
    get "/robots/nope"
    assert_equal 404, last_response.status
  end

  def test_post_without_csrf_token_is_forbidden
    post "/robots/echo/chat", message: "hi"
    assert_equal 403, last_response.status
  end

  def test_chat_fallback_returns_rendered_messages
    post "/robots/echo/chat", { message: "hi" }, csrf_header
    assert last_response.ok?
    assert_includes last_response.body, "reply: hi"
    assert_includes last_response.body, "echo"
  end

  def test_stream_emits_sse_frames_ending_in_done
    post "/robots/echo/stream", { message: "ping" }, csrf_header
    assert last_response.ok?
    assert_includes last_response.headers["Content-Type"], "text/event-stream"
    body = last_response.body
    assert_includes body, "event: message"
    assert_includes body, '"role":"user"'
    assert_includes body, '"role":"delta"'
    assert_includes body, '"role":"tool_result"'
    assert_includes body, "event: done"
    assert_includes body, "reply: ping"
  end

  private

  # Establish a session (GET sets the CSRF token) and return a header hash
  # carrying that token for a subsequent POST.
  def csrf_header
    get "/"
    { "HTTP_X_CSRF_TOKEN" => last_request.env["rack.session"][:csrf] }
  end
end
