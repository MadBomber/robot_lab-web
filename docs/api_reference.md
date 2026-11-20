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

Lazily requires `"robot_lab/web/app"` (pulling in Sinatra/Phlex on first call; Falcon is loaded only by `exe/robot_lab-web`) and returns the `App` class — a Rack app, suitable for `run RobotLab::Web.app` in a `config.ru`.

### `Error`

`RobotLab::Web::Error < StandardError` — reserved for gem-specific error conditions. Not currently raised by any code path in this gem's own logic.

### `VERSION`

`RobotLab::Web::VERSION` — the gem version string (`"0.6.1"`).

---

## `RobotLab::Web::Event`

```ruby
Event = Struct.new(:role, :content, :robot_name, :timestamp, :event_id, keyword_init: true)
```

Immutable: on construction the event freezes itself and holds a deep-frozen *copy* of the `content` it was given (nested Hashes, Arrays and Strings are copied, so the caller's own objects are never frozen; any other object is stored as-is). See [How It Works — The Event Model](how_it_works.md#the-event-model) for the full role/content table.

### `new(role:, content:, robot_name: nil, timestamp: nil, event_id: nil)`

Raises `ArgumentError` if `role` isn't one of `Event::ROLES` (`:user`, `:delta`, `:robot`, `:tool_call`, `:tool_result`, `:error`; the same array is also reachable as `RobotLab::Web::ROLES`), including when it is `nil`. `role` is coerced with `#to_sym`, so a String role works. `timestamp` defaults to `Time.now.utc`; `event_id` defaults to `SecureRandom.uuid`.

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

Rebuilds an `Event` from a Hash with either symbol or string keys (as produced by parsing JSON). Returns `nil` instead of raising if the role is missing or not a permitted one, or the timestamp string is not valid ISO 8601 (`ArgumentError` is rescued). A missing timestamp becomes `Time.now.utc`; a missing `event_id` gets a fresh UUID.

---

## `RobotLab::Web::EventSink` (module)

The thread-local hook-to-consumer bridge. See [How It Works](how_it_works.md#eventsink-a-thread-local-mailbox). The sink is held in `Thread.current[EventSink::KEY]` (`KEY = :robot_lab_web_event_sink`), which Ruby scopes to the current fiber.

### `capture(sink) { ... } → Object`

Installs `sink` (anything responding to `#call`) as the current consumer for the duration of the block, restoring whatever was previously installed (supports nesting) once the block returns or raises.

### `current → #call, nil`

The sink installed by the innermost enclosing `capture` call on this thread (and fiber), or `nil`.

### `emit(event) → void`

Delivers `event` to `current` if one is installed. Any `StandardError` the sink raises is caught and discarded — a broken consumer must never break the run it's observing.

---

## `RobotLab::Web::ActivityLog`

A thread-safe, bounded ring buffer. See [How It Works](how_it_works.md#activitylog).

### Class methods (delegate to a process-wide singleton, `ActivityLog.instance`)

| Method | Description |
|---|---|
| `log(type, details = {})` | Records an entry (`{type:, details:, timestamp:}`, with `type` coerced via `#to_sym` and a UTC `timestamp`); raises `NoMethodError` if `type` doesn't respond to `#to_sym`. `details` is stored as given, unvalidated |
| `safe_log(type, details = {})` | Same, but swallows any `StandardError` (returning `nil`) — use this from instrumentation paths |
| `recent(limit = 10)` | The `limit` most recent entries, newest first |
| `clear` | Empties the log |
| `instance` | The process-wide singleton the methods above delegate to |

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

### `store → Hash`

The underlying name-to-robot `Hash` itself (memoized, mutable, not synchronized).

---

## `RobotLab::Web::StreamHook`

`RobotLab::Hook` subclass, `namespace = :web_stream`. See [How It Works — The Hook-to-Sink Bridge](how_it_works.md#the-hook-to-sink-bridge) for the full callback table. Not instantiated directly — registered per-run via `robot.run(message, hooks: [RobotLab::Web::StreamHook])`, which is exactly what `RobotLab::Web.run` does for you.

Public class methods, each taking the `robot_lab` hook context and returning the emitted `Event`: `before_run(ctx)`, `after_run(ctx)`, `before_tool_call(ctx)`, `after_tool_call(ctx)`, `on_error(ctx)`.

---

## `RobotLab::Web::App` *(requires `"robot_lab/web/app"`)*

A `Sinatra::Base` subclass — a Rack app. See [Security](security.md) for the session/CSRF/host-authorization configuration, and [How It Works — The SSE Wire Protocol](how_it_works.md#the-sse-wire-protocol) for the streaming route's frame format.

| Route | Behavior |
|---|---|
| `GET /` | Renders `Components::Dashboard` with `Registry.names` and `ActivityLog.recent(15)` |
| `GET /robots/:name` | 404s (via `Components::ErrorPage`) if unregistered; else renders `Components::Chat` |
| `POST /robots/:name/stream` | Param: `message`. `200 text/event-stream` (with `Cache-Control: no-cache`, `X-Accel-Buffering: no`) carrying one run as `message`/`done`/`error` frames — see [How It Works](how_it_works.md#the-sse-wire-protocol). A missing/empty `message` or a run that raises is still a `200`, reported as an `error` frame |
| `POST /robots/:name/chat` | Param: `message`. Runs to completion and returns `200 text/html`: the rendered transcript fragments joined by newlines (delta events excluded). `400` with body `Missing message` if `message` is missing/empty; an exception from the run is not rescued (a `500`) |

Every route other than `GET`/`HEAD`/`OPTIONS` first passes the CSRF `before` filter: without a valid token (`authenticity_token` param or `X-CSRF-Token` header) the response is `403` with body `Forbidden: invalid CSRF token`, before the robot lookup happens. With a valid token, both `POST` routes return the same `404` error page as `GET /robots/:name` for an unregistered name. `App::CSRF_SAFE_METHODS` is `%w[GET HEAD OPTIONS]`. The bundled chat page calls only the `/stream` route.

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
