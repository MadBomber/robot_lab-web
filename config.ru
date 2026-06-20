# frozen_string_literal: true

# Server-agnostic Rack entry point for robot_lab-web. Falcon is the default
# server (see exe/robot_lab-web), but any Rack server can run this file:
#
#   falcon serve -c config.ru          # boots the console at localhost:9292
#
# By default no robots are registered. Point ROBOT_LAB_WEB_BOOT at a Ruby file
# that requires robot_lab, builds your robots, and calls RobotLab::Web.register
# on each — it is loaded here before the app starts.
#
#   ROBOT_LAB_WEB_BOOT=./my_robots.rb falcon serve -c config.ru

require 'robot_lab/web'

boot = ENV.fetch('ROBOT_LAB_WEB_BOOT', nil)
require File.expand_path(boot) if boot && File.exist?(boot)

run RobotLab::Web.app
