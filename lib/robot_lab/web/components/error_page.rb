# frozen_string_literal: true

module RobotLab
  module Web
    module Components
      # The 404 page body.
      class ErrorPage < Phlex::HTML
        def initialize(message:)
          @message = message
        end

        def view_template
          h1 { "Not found" }
          p { @message }
          p do
            a(href: "/", class: "inline-flex items-center gap-1") do
              render PhlexIcons::Hero::ArrowLeft.new(class: "w-4 h-4")
              plain "Dashboard"
            end
          end
        end
      end
    end
  end
end
