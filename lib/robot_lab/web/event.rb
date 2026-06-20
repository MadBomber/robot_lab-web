# frozen_string_literal: true

require 'time'
require 'json'
require 'securerandom'

module RobotLab
  module Web
    # Frontend-neutral, immutable value object for a single step in a robot run.
    #
    # One Event model backs both the persisted transcript and the live SSE
    # stream — serialize with #to_h, rebuild with .from_h. Role validation is
    # kept strict so a bad role fails fast rather than rendering blank.
    #
    # Roles:
    #   :user        — text the human sent
    #   :delta       — one streamed token/content delta (content is the text fragment)
    #   :robot       — the robot's final reply (content is the full final text)
    #   :tool_call   — a tool invocation (content: { name:, args: })
    #   :tool_result — a tool's return (content: { name:, result:/error: })
    #   :error       — the run raised (content: { class:, message: })
    Event = Struct.new(:role, :content, :robot_name, :timestamp, :event_id, keyword_init: true) do
      ROLES = %i[user delta robot tool_call tool_result error].freeze # rubocop:disable Lint/ConstantDefinitionInBlock

      def initialize(role:, content:, robot_name: nil, timestamp: nil, event_id: nil)
        role = role.to_sym
        raise ArgumentError, "invalid role: #{role.inspect} (expected one of #{ROLES.inspect})" unless ROLES.include?(role)

        super(
          role: role,
          content: deep_freeze(content),
          robot_name: robot_name,
          timestamp: timestamp || Time.now.utc,
          event_id: event_id || SecureRandom.uuid
        )
        freeze
      end

      # --- Convenience readers so callers never reach into the content hash ---

      def tool_name
        content.is_a?(Hash) ? (content[:name] || content['name']) : nil
      end

      def error?
        role == :error
      end

      def error_message
        return nil unless error?

        content.is_a?(Hash) ? (content[:message] || content['message']) : content.to_s
      end

      # The display text for this event, whatever its role.
      def text
        return content unless content.is_a?(Hash)

        content[:result] || content[:message] || content[:args] || content
      end

      # --- Serialization (round-trips through JSON for SSE + storage) ---

      def to_h
        {
          role: role,
          content: content,
          robot_name: robot_name,
          timestamp: timestamp.iso8601(3),
          event_id: event_id
        }
      end

      def self.from_h(hash)
        fetch = ->(key) { hash.key?(key) ? hash[key] : hash[key.to_s] }
        ts = fetch.call(:timestamp)
        new(
          role: fetch.call(:role)&.to_sym,
          content: fetch.call(:content),
          robot_name: fetch.call(:robot_name),
          timestamp: ts ? Time.iso8601(ts) : Time.now.utc,
          event_id: fetch.call(:event_id)
        )
      rescue ArgumentError
        nil
      end

      private

      def deep_freeze(obj)
        case obj
        when Hash
          obj.each_value { |v| deep_freeze(v) }
          obj.freeze
        when Array
          obj.each { |v| deep_freeze(v) }
          obj.freeze
        when String
          obj.freeze
        else
          obj
        end
      end
    end
  end
end
