# frozen_string_literal: true

# Example boot file for robot_lab-web.
#
#   robot_lab-web examples/boot.rb
#   # or
#   ROBOT_LAB_WEB_BOOT=examples/boot.rb rackup
#
# Build whatever robots you want and register each one. The web console reads
# the registry to list and drive them. Actually running a robot requires the
# provider API key for its model (e.g. ANTHROPIC_API_KEY).

require "robot_lab"
require "robot_lab/web"

assistant = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a concise, friendly assistant."
)

RobotLab::Web.register(assistant)

# Register as many as you like:
# RobotLab::Web.register(RobotLab.build(name: "support", template: :support))
