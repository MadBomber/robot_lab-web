## [Unreleased]

### Changed
- Use **Falcon** as the application server (replacing Puma). Its async/fiber
  reactor is the right fit for the long-lived SSE streams this console serves —
  fiber-per-connection concurrency, verified with two interleaving streams. The
  `exe` launches a single Falcon reactor; `config.ru` stays server-agnostic.
- Style with **Tailwind CSS** (Play CDN) instead of hand-rolled CSS. The dark
  theme is preserved; styles are Tailwind utilities composed via `@apply` so the
  server-rendered and JS-built message bubbles share one definition.
- Render views as **Phlex components** (replacing Slim) — `Layout`, `Dashboard`,
  `Chat`, `Message`, `ErrorPage` — via `phlex-sinatra`, with inline SVG icons
  from `phlex-icons-hero`. Drops the `slim` dependency.

### Added
- Core (Sinatra-free) surface: `RobotLab::Web::Event` (immutable, role-validated,
  `to_h`/`from_h`), `ActivityLog` (bounded thread-safe ring buffer), `EventSink`
  (thread-local capture), and `Registry` (in-memory robot registry).
- `RobotLab::Web::StreamHook` — taps robot_lab's hook system and turns each
  run/tool/error moment into an `Event` delivered to the current sink.
- `RobotLab::Web.run(robot, message) { |event| ... }` — stream a run's events
  from plain Ruby.
- Token-delta streaming: `RobotLab::Web.run` passes a streaming block to the
  robot, emitting a `:delta` event per RubyLLM content chunk so the reply renders
  token by token. Deltas bypass the `ActivityLog`; the final `:robot` event still
  carries the whole reply. The browser accumulates deltas into a live bubble.
- Opt-in Sinatra app (`require "robot_lab/web/app"`): dashboard, chat page,
  `POST /robots/:name/stream` (Server-Sent Events) and a non-streaming
  `POST /robots/:name/chat` HTMX fallback. CSRF + hashed session secret +
  cookie hardening + production boot guard.
- `robot_lab-web` executable and `config.ru` launcher; `examples/boot.rb`.

## [0.1.0] - 2026-06-20

- Initial release
