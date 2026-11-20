# frozen_string_literal: true

require "test_helper"

class RobotLab::Web::TestEvent < Minitest::Test
  Event = RobotLab::Web::Event

  def test_requires_a_valid_role
    assert_raises(ArgumentError) { Event.new(role: :bogus, content: "x") }
  end

  def test_accepts_string_role_and_symbolizes
    assert_equal :user, Event.new(role: "user", content: "hi").role
  end

  def test_delta_is_a_valid_role
    assert_equal :delta, Event.new(role: :delta, content: "tok").role
  end

  def test_is_frozen_and_deep_freezes_content
    event = Event.new(role: :tool_call, content: { name: "calc", args: { a: 1 } })
    assert event.frozen?
    assert event.content.frozen?
    assert event.content[:args].frozen?
  end

  def test_defaults_timestamp_and_event_id
    event = Event.new(role: :robot, content: "ok")
    assert_kind_of Time, event.timestamp
    assert_match(/\A[0-9a-f-]{36}\z/, event.event_id)
  end

  def test_tool_name_reader
    event = Event.new(role: :tool_call, content: { name: "lookup", args: {} })
    assert_equal "lookup", event.tool_name
  end

  def test_error_readers
    event = Event.new(role: :error, content: { class: "RuntimeError", message: "boom" })
    assert event.error?
    assert_equal "boom", event.error_message
  end

  def test_text_for_plain_string
    assert_equal "hello", Event.new(role: :robot, content: "hello").text
  end

  def test_to_h_and_from_h_round_trip
    original = Event.new(role: :user, content: "round trip", robot_name: "bot")
    rebuilt = Event.from_h(JSON.parse(JSON.generate(original.to_h)))
    assert_equal original.role, rebuilt.role
    assert_equal original.content, rebuilt.content
    assert_equal original.robot_name, rebuilt.robot_name
    assert_equal original.event_id, rebuilt.event_id
    assert_in_delta original.timestamp.to_f, rebuilt.timestamp.to_f, 0.001
  end

  def test_roles_constant_is_reachable_through_event
    assert_equal %i[user delta robot tool_call tool_result error], Event::ROLES
    assert_same RobotLab::Web::ROLES, Event::ROLES
  end

  def test_nil_role_is_an_argument_error
    assert_raises(ArgumentError) { Event.new(role: nil, content: "x") }
  end

  def test_from_h_returns_nil_for_missing_or_invalid_role
    assert_nil Event.from_h({})
    assert_nil Event.from_h("content" => "x")
    assert_nil Event.from_h("role" => "bogus", "content" => "x")
  end

  # Content usually aliases live objects (the args a tool is about to be
  # called with); the Event must freeze its own copy, never the caller's.
  def test_does_not_freeze_the_callers_content_in_place
    text = +"hello"
    list = [text]
    args = { text: text, list: list }
    event = Event.new(role: :tool_call, content: { name: "echo", args: args })

    refute args.frozen?
    refute list.frozen?
    refute text.frozen?
    assert event.content[:args].frozen?
    assert event.content[:args][:list].frozen?
    assert event.content[:args][:text].frozen?
    assert_equal args, event.content[:args]
  end
end
