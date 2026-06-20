# frozen_string_literal: true

module RobotLab
  module Web
    # In-memory registry of the robots the web UI can drive, keyed by name.
    # The host app registers robots at boot; the Sinatra app reads from here.
    module Registry
      module_function

      def store
        @store ||= {}
      end

      # Register a robot (anything responding to #run and #name).
      def register(robot, name: nil)
        key = (name || robot.name).to_s
        store[key] = robot
        key
      end

      def fetch(name)
        store[name.to_s]
      end

      def names
        store.keys.sort
      end

      def all
        store.values
      end

      def clear
        store.clear
      end
    end
  end
end
