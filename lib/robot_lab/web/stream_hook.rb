# frozen_string_literal: true

require_relative 'event'
require_relative 'event_sink'
require_relative 'activity_log'

module RobotLab
  module Web
    # Taps robot_lab's hook system and turns each lifecycle moment into a
    # RobotLab::Web::Event, delivered to the current EventSink and recorded in
    # the ActivityLog. This is the producer half of the `on_event -> SSE`
    # bridge that drives the browser console.
    #
    # Register per-run so it only fires for web-driven runs:
    #   robot.run(message, hooks: [RobotLab::Web::StreamHook])
    # ...inside an EventSink.capture { } block.
    class StreamHook < RobotLab::Hook
      self.namespace = :web_stream

      class << self
        def before_run(ctx)
          emit(ctx, role: :user, content: ctx.request.to_s)
        end

        def after_run(ctx)
          if ctx.error
            emit_error(ctx, ctx.error)
          else
            emit(ctx, role: :robot, content: final_text(ctx.response))
          end
        end

        def before_tool_call(ctx)
          emit(ctx, role: :tool_call, content: { name: ctx.tool_name, args: ctx.tool_args })
        end

        def after_tool_call(ctx)
          content =
            if ctx.tool_error
              { name: ctx.tool_name, error: ctx.tool_error.message }
            else
              { name: ctx.tool_name, result: ctx.tool_result }
            end
          emit(ctx, role: :tool_result, content: content)
        end

        def on_error(ctx)
          emit_error(ctx, ctx.error)
        end

        private

        def emit(ctx, role:, content:)
          event = Event.new(role: role, content: content, robot_name: robot_name(ctx))
          EventSink.emit(event)
          ActivityLog.safe_log(role, robot: event.robot_name, tool: event.tool_name)
          event
        end

        def emit_error(ctx, error)
          emit(ctx, role: :error, content: { class: error.class.name, message: error.message })
        end

        def robot_name(ctx)
          ctx.respond_to?(:robot) && ctx.robot ? ctx.robot.name : nil
        end

        def final_text(response)
          return response.reply if response.respond_to?(:reply)
          return response.last_text_content if response.respond_to?(:last_text_content)

          response.to_s
        end
      end
    end
  end
end
