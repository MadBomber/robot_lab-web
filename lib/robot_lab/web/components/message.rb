# frozen_string_literal: true

module RobotLab
  module Web
    module Components
      # One transcript message. Used server-side for the non-streaming /chat
      # fallback; the SSE client builds the same markup (same classes) in JS.
      class Message < Phlex::HTML
        def initialize(event:)
          @event = event
        end

        def view_template
          div(class: "msg #{@event.role}") do
            div(class: "role") { plain role_header }
            plain body_text
          end
        end

        private

        def role_header
          @event.robot_name ? "#{@event.role} · #{@event.robot_name}" : @event.role.to_s
        end

        def body_text
          c = @event.content
          case @event.role
          when :tool_call
            "#{@event.tool_name}(#{c[:args].to_json})"
          when :tool_result
            c[:error] ? "#{@event.tool_name} → error: #{c[:error]}" : "#{@event.tool_name} → #{c[:result]}"
          when :error
            @event.error_message.to_s
          else
            @event.text.to_s
          end
        end
      end
    end
  end
end
