# frozen_string_literal: true

require_relative 'web/version'

# Core (Sinatra-free) surface of robot_lab-web. Requiring this gives you the
# event model, activity log, sink, registry, and — when robot_lab is loaded —
# the StreamHook. The Sinatra app and its heavy deps (sinatra, falcon, phlex) are
# opt-in: `require "robot_lab/web/app"`, which keeps the web stack off the core
# load path.
require_relative 'web/event'
require_relative 'web/activity_log'
require_relative 'web/event_sink'
require_relative 'web/registry'

# robot_lab is a hard dependency: StreamHook subclasses RobotLab::Hook. Require
# it here so load order never matters (the exe/config.ru may require this file
# before a user boot script gets to require "robot_lab").
require 'robot_lab'
require_relative 'web/stream_hook'

module RobotLab
  # Browser front end for a robot_lab project: stream a robot's run to a web
  # page over Server-Sent Events (an on_event -> SSE bridge, an immutable Event
  # value object, an in-memory ActivityLog, and a hardened dev-tool security
  # posture).
  module Web
    class Error < StandardError; end

    module_function

    # Register a robot the web UI can drive. Returns the string key.
    #
    #   RobotLab::Web.register(my_robot)
    #   RobotLab::Web.register(my_robot, name: "support")
    def register(robot, name: nil)
      Registry.register(robot, name: name)
    end

    # Run +robot+ against +message+, delivering each lifecycle Event to +sink+
    # (a callable taking an Event) as it happens, and returning the robot's
    # RobotResult. This is the one call the web routes wrap; it is also the
    # cleanest way to consume the stream from plain Ruby or a test.
    #
    # Two layers of events arrive at the sink:
    #   * StreamHook turns robot_lab hook moments into :user / :tool_call /
    #     :tool_result / :robot / :error events.
    #   * the streaming block below turns each RubyLLM content chunk into a
    #     :delta event, so the reply can be rendered token by token. (A model or
    #     run that doesn't stream simply produces no deltas — the final :robot
    #     event still carries the whole reply.)
    #
    #   events = []
    #   RobotLab::Web.run(robot, "hello") { |event| events << event }
    def run(robot, message, sink = nil, &block)
      sink ||= block
      name = robot.respond_to?(:name) ? robot.name : nil
      EventSink.capture(sink) do
        robot.run(message, hooks: [StreamHook]) do |chunk|
          delta = chunk.respond_to?(:content) ? chunk.content : chunk.to_s
          next if delta.nil? || delta.empty?

          # Emit straight to the sink — deltas bypass the ActivityLog so token
          # spam never floods the dashboard's recent-activity feed.
          EventSink.emit(Event.new(role: :delta, content: delta, robot_name: name))
        end
      end
    end

    # Boot the Sinatra app. Requires the opt-in web stack on first call.
    #
    #   RobotLab::Web.app  # => RobotLab::Web::App (a Rack app)
    def app
      require_relative 'web/app'
      App
    end
  end
end
