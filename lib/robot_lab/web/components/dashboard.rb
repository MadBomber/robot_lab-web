# frozen_string_literal: true

module RobotLab
  module Web
    module Components
      # The dashboard: registered robots + the recent-activity feed.
      class Dashboard < Phlex::HTML
        def initialize(robots:, activity:)
          @robots = robots
          @activity = activity
        end

        def view_template
          h1 { "Robots" }
          if @robots.empty?
            p { "No robots registered. In your boot script:" }
            pre { %(require "robot_lab/web"\n\nRobotLab::Web.register(my_robot)) }
          else
            ul(class: "robots") do
              @robots.each do |name|
                li { a(href: "/robots/#{name}") { name } }
              end
            end
          end

          h2 { "Recent activity" }
          if @activity.empty?
            p(class: "muted") { "Nothing yet." }
          else
            ul(class: "activity") do
              @activity.each { |entry| li { plain activity_line(entry) } }
            end
          end
        end

        private

        def activity_line(entry)
          parts = [entry[:timestamp].strftime("%H:%M:%S"), entry[:type].to_s]
          details = (entry[:details] || {}).compact
          parts << details.map { |k, v| "#{k}=#{v}" }.join(" ") unless details.empty?
          parts.join(" · ")
        end
      end
    end
  end
end
