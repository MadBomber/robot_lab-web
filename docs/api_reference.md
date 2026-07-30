# API Reference

Every public class, module, and method in `robot_lab-web`. See [How It Works](how_it_works.md) for the concepts behind each one.

## `RobotLab::Web` (module)

### `register(robot, name: nil) → String`

Registers `robot` (anything responding to `#run` and `#name`) so the console can list and drive it. Returns the string key it was stored under. Delegates to `Registry.register`.

```ruby
RobotLab::Web.register(assistant)
RobotLab::Web.register(assistant, name: "support")
```

### `run(robot, message, sink = nil, &block) → RobotResult`

Runs `robot` against `message`, delivering each lifecycle `Event` to `sink` (or `block`, if `sink` is omitted) as it happens, and returning the robot's `RobotResult` once the run completes. This is the one call both Sinatra routes wrap, and the cleanest way to consume the stream from plain Ruby or a test. See [How It Works — `RobotLab::Web.run`](how_it_works.md#robotlabwebrun-the-one-call-that-ties-it-together) for exactly what it wires up.

```ruby
events = []
RobotLab::Web.run(assistant, "hello") { |event| events << event }
```

### `app → RobotLab::Web::App`

Lazily requires `"robot_lab/web/app"` (pulling in Sinatra/Falcon/Phlex on first call) and returns the `App` class — a Rack app, suitable for `run RobotLab::Web.app` in a `config.ru`.

### `Error`

`RobotLab::Web::Error < StandardError` — reserved for gem-specific error conditions. Not currently raised by any code path in this gem's own logic.

---

## `RobotLab::Web::Event`

```ruby
Event = Struct.new(:role, :content, :robot_name, :timestamp, :event_id, keyword_init: true)
```

Immutable (deep-frozen on construction). See [How It Works — The Event Model](how_it_works.md#the-event-model) for the full role/content table.

### `new(role:, content:, robot_name: nil, timestamp: nil, event_id: nil)`

Raises `ArgumentError` if `role` isn't one of `Event::ROLES` (`:user`, `:delta`, `:robot`, `:tool_call`, `:tool_result`, `:error`). `timestamp` defaults to `Time.now.utc`; `event_id` defaults to `SecureRandom.uuid`.

### Readers

`role`, `content`, `robot_name`, `timestamp`, `event_id` — plain `Struct` readers.

### `tool_name → String, nil`

`content[:name]`/`content['name']` when `content` is a Hash (works for both `:tool_call` and `:tool_result`); `nil` otherwise.

### `error? → Boolean`

`true` when `role == :error`.

### `error_message → String, nil`

`content[:message]`/`content['message']` (or `content.to_s` for a non-Hash) when `error?`; `nil` otherwise.

### `text → Object`

A role-agnostic display value: for Hash content, `content[:result] || content[:message] || content[:args] || content`; for anything else, `content` itself unchanged.

### `to_h → Hash`

`{role:, content:, robot_name:, timestamp: (ISO 8601, ms precision), event_id:}` — JSON-serializable.

### `self.from_h(hash) → Event, nil`

Rebuilds an `Event` from a Hash with either symbol or string keys (as produced by parsing JSON). Returns `nil` instead of raising if the role fails validation.

---

## `RobotLab::Web::EventSink` (module)

The thread-local hook-to-consumer bridge. See [How It Works](how_it_works.md#eventsink-a-thread-local-mailbox).

### `capture(sink) { ... } → Object`

Installs `sink` (anything responding to `#call`) as the current consumer for the duration of the block, restoring whatever was previously installed (supports nesting) once the block returns or raises.

### `current → #call, nil`

The sink installed by the innermost enclosing `capture` call on this thread, or `nil`.

### `emit(event) → void`

Delivers `event` to `current` if one is installed. Any `StandardError` the sink raises is caught and discarded — a broken consumer must never break the run it's observing.

---

## `RobotLab::Web::ActivityLog`

A thread-safe, bounded ring buffer. See [How It Works](how_it_works.md#activitylog).

### Class methods (delegate to a process-wide singleton, `ActivityLog.instance`)

| Method | Description |
|---|---|
| `log(type, details = {})` | Records an entry (`{type:, details:, timestamp:}`); raises if `type`/`details` are malformed |
| `safe_log(type, details = {})` | Same, but swallows any error — use this from instrumentation paths |
| `recent(limit = 10)` | The `limit` most recent entries, newest first |
| `clear` | Empties the log |

### Instance

`MAX_EVENTS = 50` — the ring buffer's capacity; oldest entries are dropped once exceeded. `#log`/`#recent`/`#clear` are the same operations, mutex-guarded, on a fresh instance if you don't want the process-wide singleton (mainly useful in tests).

---

## `RobotLab::Web::Registry` (module)

An in-memory `Hash` of registered robots, keyed by name. See [How It Works](how_it_works.md#registry).

### `Registry.register(robot, name: nil) → String`

Stores `robot` under `(name || robot.name).to_s`, returning that key.

### `fetch(name) → robot, nil`

Looks up a registered robot by name (coerced to `String`).

### `names → Array<String>`

All registered names, alphabetically sorted.

### `all → Array`

All registered robot objects, in insertion order.

### `clear → void`

Empties the registry — mainly useful in tests.

---

## `RobotLab::Web::StreamHook`

`RobotLab::Hook` subclass, `namespace = :web_stream`. See [How It Works — The Hook-to-Sink Bridge](how_it_works.md#the-hook-to-sink-bridge) for the full callback table. Not instantiated directly — registered per-run via `robot.run(message, hooks: [RobotLab::Web::StreamHook])`, which is exactly what `RobotLab::Web.run` does for you.

---

## `RobotLab::Web::App` *(requires `"robot_lab/web/app"`)*

A `Sinatra::Base` subclass — a Rack app. See [Security](security.md) for the session/CSRF/host-authorization configuration, and [How It Works — The SSE Wire Protocol](how_it_works.md#the-sse-wire-protocol) for the streaming route's frame format.

| Route | Behavior |
|---|---|
| `GET /` | Renders `Components::Dashboard` with `Registry.names` and `ActivityLog.recent(15)` |
| `GET /robots/:name` | 404s (via `Components::ErrorPage`) if unregistered; else renders `Components::Chat` |
| `POST /robots/:name/stream` | SSE stream of one run — see [How It Works](how_it_works.md#the-sse-wire-protocol) |
| `POST /robots/:name/chat` | Runs to completion, returns rendered transcript HTML fragments (delta events excluded) |

`self.session_secret_source` / `self.persisted_dev_secret` — the session-secret resolution logic; see [Security — Session Secret](security.md#session-secret-persistence).

---

## `RobotLab::Web::Components` *(requires `"robot_lab/web/app"`)*

Phlex (`Phlex::HTML`) view components, each a small, focused constructor + `view_template`:

| Component | Constructor | Renders |
|---|---|---|
| `Layout` | `new(csrf:, content:)` | The HTML document shell — Tailwind CDN + shared styles, top nav, and the wrapped page `content` |
| `Dashboard` | `new(robots:, activity:)` | Registered robot list + recent-activity feed |
| `Chat` | `new(name:)` | The transcript container, composer form, and the inline vanilla-JS SSE streaming client |
| `Message` | `new(event:)` | One transcript message from an `Event` — used server-side by the non-streaming `/chat` fallback |
| `ErrorPage` | `new(message:)` | The 404 page body |

These aren't meant to be used outside `App` itself, but are documented here since they're real, independently-instantiable public classes (not `private_constant`).
