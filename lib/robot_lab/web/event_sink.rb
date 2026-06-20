# frozen_string_literal: true

module RobotLab
  module Web
    # The bridge between robot_lab's synchronous hook dispatch and a consumer
    # (an SSE stream, a collecting array, anything responding to #call).
    #
    # robot_lab hooks are class-level singletons, so there is no instance on
    # which to hang a per-connection callback. We instead stash the consumer in
    # a thread-local for the duration of a run. Because Robot#run dispatches its
    # hooks synchronously on the calling thread, the StreamHook sees the right
    # sink. (Caveat: a robot that executes tools on other threads/Ractors would
    # not propagate this — fine for the core synchronous path.)
    #
    # In effect this gives a robot run an `on_event:` callback without changing
    # robot_lab's API.
    module EventSink
      KEY = :robot_lab_web_event_sink

      module_function

      # Run the block with +sink+ (any callable taking an Event) installed as
      # the current consumer. Restores the previous sink afterward.
      def capture(sink)
        previous = Thread.current[KEY]
        Thread.current[KEY] = sink
        yield
      ensure
        Thread.current[KEY] = previous
      end

      def current
        Thread.current[KEY]
      end

      # Deliver an Event to the current sink (if any). Never raises into the
      # run — a broken consumer must not break the robot.
      def emit(event)
        sink = current
        sink&.call(event)
      rescue StandardError
        nil
      end
    end
  end
end
