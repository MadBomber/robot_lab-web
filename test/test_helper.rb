# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Load robot_lab first so RobotLab::Hook exists and StreamHook is defined.
require "robot_lab"
require "robot_lab/web"

require "minitest/autorun"
