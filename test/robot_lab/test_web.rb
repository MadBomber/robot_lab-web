# frozen_string_literal: true

require "test_helper"

class RobotLab::TestWeb < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::RobotLab::Web::VERSION
  end

  def test_stream_hook_is_defined_when_robot_lab_is_loaded
    assert defined?(RobotLab::Web::StreamHook)
    assert_operator RobotLab::Web::StreamHook, :<, RobotLab::Hook
  end
end
