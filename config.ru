# frozen_string_literal: true

# Rackup entry point for robot_lab-web.
#
#   rackup            # boots the console at http://localhost:9292
#
# By default no robots are registered. Point ROBOT_LAB_WEB_BOOT at a Ruby file
# that requires robot_lab, builds your robots, and calls RobotLab::Web.register
# on each — it is loaded here before the app starts.
#
#   ROBOT_LAB_WEB_BOOT=./my_robots.rb rackup

require 'robot_lab/web'

boot = ENV.fetch('ROBOT_LAB_WEB_BOOT', nil)
require File.expand_path(boot) if boot && File.exist?(boot)

run RobotLab::Web.app
