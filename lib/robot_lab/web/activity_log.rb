# frozen_string_literal: true

require 'time'

module RobotLab
  module Web
    # Thread-safe, bounded, in-memory ring buffer for a dashboard "recent
    # activity" feed.
    #
    # The cardinal rule, enforced by .safe_log: instrumentation must never
    # break the request that triggered it.
    class ActivityLog
      MAX_EVENTS = 50

      class << self
        def instance
          @instance ||= new
        end

        def log(type, details = {})
          instance.log(type, details)
        end

        # Record an event, swallowing any error.
        def safe_log(type, details = {})
          log(type, details)
        rescue StandardError
          nil
        end

        def recent(limit = 10)
          instance.recent(limit)
        end

        def clear
          instance.clear
        end
      end

      def initialize
        @events = []
        @mutex = Mutex.new
      end

      def log(type, details = {})
        @mutex.synchronize do
          @events.unshift(type: type.to_sym, details: details, timestamp: Time.now.utc)
          @events = @events.first(MAX_EVENTS)
        end
      end

      def recent(limit = 10)
        @mutex.synchronize { @events.first(limit) }
      end

      def clear
        @mutex.synchronize { @events = [] }
      end
    end
  end
end
