# frozen_string_literal: true

# Example boot file for robot_lab-web.
#
#   robot_lab-web examples/boot.rb
#   # or
#   ROBOT_LAB_WEB_BOOT=examples/boot.rb rackup
#
# Build whatever robots you want and register each one. The web console reads
# the registry to list and drive them. This boot file drives a local LM Studio
# model through the :lms provider — start the server first (lms server start).

require "robot_lab"
require "robot_lab/web"
require "ruby_llm/providers/lms"

assistant = RobotLab.build(
  name: "assistant",
  provider: "lms",
  model: ENV.fetch("LMS_MODEL", "openai/gpt-oss-20b"),
  system_prompt: "You are a concise, friendly assistant."
)

RobotLab::Web.register(assistant)

# Register as many as you like:
# RobotLab::Web.register(RobotLab.build(name: "support", template: :support))
