# How It Works

## Core vs. Opt-In Web Stack

`robot_lab-web` is split into two load paths:

- **`require "robot_lab/web"`** — the core, Sinatra-free surface: `Event`, `ActivityLog`, `EventSink`, `Registry`, and (since `robot_lab` is a hard dependency, required directly by this file so load order never matters) `StreamHook`. No Sinatra, Falcon, or Phlex touched at all — this is everything `RobotLab::Web.run`/`.register` need, and everything a test or a custom front end needs too.
- **`require "robot_lab/web/app"`** (or simply call `RobotLab::Web.app`, which requires it lazily on first use) — pulls in Sinatra, `phlex-sinatra`, `phlex-icons-hero`, and the bundled `App` class plus its Phlex view components.

This split exists so that consuming the event stream from plain Ruby (a test, a script, an alternate front end) never has to load Sinatra/Falcon/Phlex at all — those are only paid for when you actually want the bundled console.

## The Event Model

`RobotLab::Web::Event` is a frontend-neutral, **immutable** value object for a single step in a robot run — the one model backing both the persisted (in-memory) activity log and the live SSE stream. It's a `Struct` (keyword-init) that deep-freezes its `content` on construction (recursively, through nested Hashes/Arrays/Strings) and freezes itself, so an `Event` handed to a sink can never be mutated by that sink afterward.

| Role | `content` shape | Meaning |
|---|---|---|
| `:user` | `String` | Text the human sent |
| `:delta` | `String` | One streamed token/content fragment |
| `:robot` | `String` | The robot's final reply (the whole text, not a fragment) |
| `:tool_call` | `{name:, args:}` | A tool invocation |
| `:tool_result` | `{name:, result:}` or `{name:, error:}` | A tool's return (or its failure) |
| `:error` | `{class:, message:}` | The run itself raised |

Role validation is strict — `Event.new(role: :bogus, ...)` raises `ArgumentError` immediately rather than silently rendering a blank or malformed bubble later. Construction also stamps a UTC `timestamp` and a random `event_id` (`SecureRandom.uuid`) when not given explicitly.

Convenience readers mean callers never have to reach into the `content` hash directly: `#tool_name` (works for both `:tool_call` and `:tool_result`), `#error?`, `#error_message`, and `#text` — a role-agnostic "what should I display" reader that unwraps `content[:result]`/`content[:message]`/`content[:args]` for hash-shaped content, or returns `content` itself otherwise.

`#to_h`/`.from_h` round-trip an `Event` through JSON (used both for SSE frames and any future persistence) — `timestamp` serializes as ISO 8601 with millisecond precision; `from_h` accepts either symbol or string keys (`hash.key?(key) ? hash[key] : hash[key.to_s]`) so it can rebuild an `Event` from a hash decoded from JSON (string keys) just as easily as one built in Ruby (symbol keys), and returns `nil` rather than raising if the role can't be validated.

## The Hook-to-Sink Bridge

Two pieces work together to turn a synchronous `robot.run` call into a live event stream, without adding any new API surface to `robot_lab` core itself:

### `EventSink` — a thread-local mailbox

`robot_lab` hooks are **class-level singletons** — there's no hook instance to hang a per-connection callback on. `EventSink` works around this by stashing the current consumer (any object responding to `#call`) in a `Thread.current` slot for the duration of one run:

```ruby
EventSink.capture(sink) { robot.run(message, hooks: [StreamHook]) { |chunk| ... } }
```

Because `Robot#run` dispatches its hooks **synchronously on the calling thread**, `StreamHook` (running inside that same call) sees exactly the right sink via `EventSink.current`. `EventSink.emit(event)` delivers to it and swallows any `StandardError` the sink itself raises — a broken consumer (a dead SSE connection, a bug in a custom sink) must never break the robot run it's observing.

**Caveat, stated directly in the source:** a robot that executes tools on other threads or via Ractors would not propagate this thread-local — fine for `robot_lab`'s core synchronous tool-call path, but worth knowing if you're pairing this with `robot_lab-ractor` or similar.

### `StreamHook` — the producer

A `RobotLab::Hook` subclass (`namespace = :web_stream`) that taps every lifecycle moment `robot_lab`'s hook system exposes and turns it into an `Event`, delivered to the current `EventSink` and also recorded in `ActivityLog` (see below):

| Hook callback | Emits |
|---|---|
| `before_run` | `:user` — the incoming request text |
| `after_run` (success) | `:robot` — the final reply text (`ctx.response.reply`, falling back to `#last_text_content`, then plain `#to_s`) |
| `after_run` (error) | `:error` |
| `before_tool_call` | `:tool_call` |
| `after_tool_call` | `:tool_result` (success or error shape, depending on `ctx.tool_error`) |
| `on_error` | `:error` |

Registered **per-run**, not globally (`robot.run(message, hooks: [RobotLab::Web::StreamHook])`), so it only fires for web-driven runs — a robot used elsewhere in your app, outside the console, is completely unaffected.

### `RobotLab::Web.run` — the one call that ties it together

```ruby
def run(robot, message, sink = nil, &block)
  sink ||= block
  EventSink.capture(sink) do
    robot.run(message, hooks: [StreamHook]) do |chunk|
      delta = chunk.respond_to?(:content) ? chunk.content : chunk.to_s
      next if delta.nil? || delta.empty?
      EventSink.emit(Event.new(role: :delta, content: delta, robot_name: name))
    end
  end
end
```

This is the single call both Sinatra routes wrap, and the cleanest way to consume the stream from plain Ruby or a test. **Two independent layers of events reach the sink:**

1. `StreamHook`, translating `robot_lab` hook moments into `:user`/`:tool_call`/`:tool_result`/`:robot`/`:error` events, and
2. the streaming block passed to `robot.run` itself, translating each RubyLLM content chunk into a `:delta` event.

A model or run that doesn't stream token-by-token simply produces no `:delta` events at all — the final `:robot` event still carries the complete reply either way, so nothing is lost, only the incremental rendering.

**Deltas deliberately bypass `ActivityLog`** — `StreamHook`'s `emit` helper logs to the activity feed on every call, but the delta block above calls `EventSink.emit` directly, skipping that logging so token-by-token spam never floods the dashboard's recent-activity feed with hundreds of entries per run.

## `ActivityLog`

A thread-safe, bounded (`MAX_EVENTS` = 50) in-memory ring buffer backing the dashboard's "recent activity" feed — a process-wide singleton (`ActivityLog.instance`), not per-connection. `.safe_log` is the cardinal rule enforced everywhere this is called from instrumentation paths: swallow any error, because **recording that something happened must never be able to break the thing that happened**.

This is intentionally separate from the SSE event stream itself — the activity log is a lightweight, best-effort summary (`role`, `robot`, `tool` — see `StreamHook#emit`'s `ActivityLog.safe_log(role, robot: ..., tool: ...)` call) for the dashboard's overview, not the full transcript; the full transcript only ever exists as the live SSE stream (or whatever a custom sink chooses to persist).

## `Registry`

A plain in-memory `Hash`, keyed by robot name (string) — the host app registers robots at boot (`RobotLab::Web.register`), and the Sinatra app reads from it (`Registry.fetch`/`.names`/`.all`) to know what it can list and drive. No persistence beyond the process's own memory — restarting the console clears the registry, and it's rebuilt entirely by whatever boot file ran at start.

## The SSE Wire Protocol

`POST /robots/:name/stream` sets `content_type 'text/event-stream'` and streams frames as they happen, using Sinatra's `stream do |out| ... end`:

```ruby
write_sse = ->(type, data) { out << "event: #{type}\ndata: #{JSON.generate(data)}\n\n" }
```

Three frame types:

| `event:` | `data:` payload | When |
|---|---|---|
| `message` | `event.to_h` (a full `Event`, JSON-encoded) | Once per `Event` the run produces — every `:user`/`:delta`/`:tool_call`/`:tool_result`/`:robot`/`:error` |
| `done` | `{reply: <final text>}` | Once, after the run completes successfully |
| `error` | `{message: <text>}` | Once, if the request had no `message` param, or if the run itself raised |

**Why this isn't a plain browser `EventSource`:** the stream route is CSRF-protected (see [Security](security.md#csrf-protection)), and `EventSource` is GET-only and cannot send custom headers or a request body — there's no way to attach a CSRF token to it. The bundled `Chat` component's client-side JS instead uses `fetch()` with a `ReadableStream` reader, manually parsing the same `event:`/`data:` frame format `EventSource` would have handled natively:

```js
const res = await fetch(streamUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-CSRF-Token': csrf },
  body: 'message=' + encodeURIComponent(message)
});
const reader = res.body.getReader();
// ...decode chunks, split on "\n\n" into frames, parse "event:"/"data:" lines...
```

The parsing loop buffers incoming bytes, splits on blank lines (`\n\n`, the SSE frame delimiter) keeping the last, possibly-incomplete fragment in the buffer for the next read, and for each complete frame extracts the `event:` and `data:` lines exactly the way a native `EventSource` would internally.

## Token-Delta Rendering, Client-Side

The chat page's JS keeps a single "currently streaming" bubble reference (`streaming`) while `:delta` events arrive, appending each fragment's text (`streaming.textContent += ev.content`) so the reply grows token-by-token in place. When the terminal `:robot` event arrives, it replaces the accumulated text with the final authoritative string (`streaming.textContent = ev.content`) and clears the `streaming` reference — the delta-built text and the final `:robot` text should be identical in the normal case, but the final event is treated as the source of truth. `:user` events are skipped entirely on render — the client already rendered the user's own message optimistically, immediately on form submit, before the request even went out.

## Two Ways to Render the Same Transcript

The same `Event` → HTML mapping exists in two places, by necessity: `Components::Message` (Phlex, server-side — used by the non-streaming `/chat` fallback endpoint) and the inline JS in `Components::Chat::CLIENT_JS` (client-side — used by the streaming `/stream` endpoint's `fetch()` client). They're kept in sync intentionally (same CSS classes — `.msg`, `.msg.user`, `.msg.tool_call`, etc. — defined once in `Layout::STYLES` and shared by both renderers) but are genuinely two separate implementations, since the streaming path never touches the server-side Phlex renderer for the events it's actively streaming — only the non-streaming fallback does.

The non-streaming `/robots/:name/chat` endpoint explicitly filters out `:delta` events before rendering (`events.reject { |event| event.role == :delta }`) — since the final `:robot` event already carries the complete reply, showing the deltas too would duplicate the same text piecemeal-then-whole in a static (non-incremental) render.

## Falcon as the Application Server

`exe/robot_lab-web` builds a single `Falcon::Server` (not Puma) and calls `#run` at the top level, which blocks on the accept loop until interrupted. Falcon's async/fiber reactor gives cheap fiber-per-connection concurrency in one process — the right fit for a console serving multiple long-lived SSE streams at once, since each connection can sit open (mid-stream) for as long as a robot run takes without tying up an OS thread the way a thread-per-connection server would. `config.ru` itself stays server-agnostic — nothing in the Sinatra `App` class requires Falcon specifically; any Rack server can run it, just without that same cheap concurrency model for long-lived connections.
