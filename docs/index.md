# robot_lab-web

A Rails-free **web console for [robot_lab](https://github.com/MadBomber/robot_lab)**: register your robots, chat with them from the browser, and watch each lifecycle event — tool calls, tool results, the final reply, errors — **stream in real time** over Server-Sent Events.

It's the standalone counterpart to [`robot_lab-rails`](https://github.com/MadBomber/robot_lab-rails): one event stream, a Sinatra + HTMX front end, no Turbo and no Rails required.

```ruby
# my_robots.rb
require "robot_lab"
require "robot_lab/web"

assistant = RobotLab.build(name: "assistant", system_prompt: "You are concise.")
RobotLab::Web.register(assistant)
```

```sh
robot_lab-web my_robots.rb   # http://127.0.0.1:9292 — pick a robot, start chatting
```

!!! warning "Developer tool — unauthenticated by default"
    The console has no login. Run it on localhost or a trusted private network. It ships sensible hardening (CSRF with a constant-time compare, a hashed and persisted session secret, `httponly`/`SameSite` cookies, a production boot guard) but is **not** meant to face untrusted users. See [Security](security.md) for the full posture and its limits.

## How It Fits Together

```
browser ──POST /robots/:name/stream──▶ Sinatra App
                                         └─ RobotLab::Web.run(robot, msg) { |event| write_sse }
                                              └─ robot.run(msg, hooks: [StreamHook])
                                                   └─ StreamHook ─emits─▶ EventSink ─▶ SSE frames
```

`robot_lab-web` registers a per-run hook (`RobotLab::Web::StreamHook`) on `robot_lab`'s own hook system. As a robot runs, the hook turns each moment into an immutable `RobotLab::Web::Event` and pushes it to whatever sink is currently listening — an SSE stream for the browser, or a plain array in a test. This is `robot_lab`'s native equivalent of an `on_event:` callback, built entirely out of existing hook infrastructure rather than a new API on `Robot` itself.

## Navigation

- [Getting Started](getting_started.md) — installation, writing a boot file, launching the console, the four HTTP endpoints
- [How It Works](how_it_works.md) — the event model, the hook-to-sink bridge, the SSE wire protocol and its browser-side client, token-delta streaming, the opt-in core/Sinatra split
- [API Reference](api_reference.md) — every public class and method
- [Security](security.md) — the full hardening posture (CSRF, session secret, cookies, host authorization, production guard) and exactly what it does and doesn't protect against

## At a Glance

| | |
|---|---|
| **Server** | [Falcon](https://github.com/socketry/falcon) (async/fiber reactor — the right fit for long-lived SSE streams); `config.ru` itself is server-agnostic |
| **Views** | [Phlex](https://www.phlex.fun/) components, rendered via `phlex-sinatra`, styled with Tailwind (Play CDN), icons from `phlex-icons-hero` |
| **Front end** | Vanilla JS `fetch()` streaming client (not `EventSource` — the stream route is CSRF-protected, and `EventSource` can't send custom headers) plus an HTMX-compatible non-streaming fallback |
| **Core dependency** | `require "robot_lab/web"` alone gets you the event model, activity log, sink, and registry — no Sinatra/Falcon/Phlex loaded |
| **Opt-in web stack** | `require "robot_lab/web/app"` (or call `RobotLab::Web.app`) pulls in Sinatra, Falcon, and Phlex |
| **Endpoints** | `GET /`, `GET /robots/:name`, `POST /robots/:name/stream` (SSE), `POST /robots/:name/chat` (non-streaming HTMX fallback) |
| **Hook used** | `RobotLab::Web::StreamHook`, registered per-run (`hooks: [StreamHook]`), not globally |

## Links

- [RobotLab Core](https://github.com/MadBomber/robot_lab)
- [robot_lab-rails](https://github.com/MadBomber/robot_lab-rails) — the Rails/Turbo counterpart to this gem
- [RubyGems](https://rubygems.org/gems/robot_lab-web)
- [GitHub](https://github.com/MadBomber/robot_lab-web)
- [Changelog](https://github.com/MadBomber/robot_lab-web/blob/main/CHANGELOG.md)
