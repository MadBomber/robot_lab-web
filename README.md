# RobotLab::Web

A Rails-free **web console for [robot_lab](../robot_lab)**: register your robots,
chat with them from the browser, and watch each lifecycle event — tool calls,
tool results, the final reply, errors — **stream in real time** over
Server-Sent Events.

It's the standalone counterpart to `robot_lab-rails`: one event stream, a
Sinatra + HTMX front end, no Turbo and no Rails required.

> ⚠️ **Developer tool.** The console is **unauthenticated by default**. Run it on
> localhost or a trusted private network. It ships sensible hardening (CSRF with
> constant-time compare, a hashed session secret, `httponly`/`SameSite` cookies,
> a production boot guard) but is not meant to face untrusted users.

## How it works

`robot_lab-web` registers a per-run hook (`RobotLab::Web::StreamHook`) on
robot_lab's own hook system. As a robot runs, the hook turns each moment into an
immutable `RobotLab::Web::Event` and pushes it to the current sink — an SSE
stream for the browser, or a plain array in tests. This is robot_lab's native
equivalent of an `on_event:` callback.

```
browser ──POST /robots/:name/stream──▶ Sinatra App
                                         └─ RobotLab::Web.run(robot, msg) { |event| write_sse }
                                              └─ robot.run(msg, hooks: [StreamHook])
                                                   └─ StreamHook ─emits─▶ EventSink ─▶ SSE frames
```

## Usage

Write a boot file that builds your robots and registers each one:

```ruby
# my_robots.rb
require "robot_lab"
require "robot_lab/web"

assistant = RobotLab.build(name: "assistant", system_prompt: "You are concise.")
RobotLab::Web.register(assistant)
```

Launch the console (Falcon):

```bash
robot_lab-web my_robots.rb            # http://127.0.0.1:9292
robot_lab-web --port 4567 my_robots.rb
```

…or point Falcon (or any Rack server) at the server-agnostic `config.ru`:

```bash
ROBOT_LAB_WEB_BOOT=my_robots.rb falcon serve -c config.ru
```

Then open the dashboard, pick a robot, and chat. (Running a robot needs the
provider key for its model, e.g. `ANTHROPIC_API_KEY`.)

### Consuming the stream from Ruby

The same path the web routes use is available directly — handy for tests or a
custom front end:

```ruby
RobotLab::Web.run(assistant, "Hello") do |event|
  puts "#{event.role}: #{event.text}"
end
```

## Endpoints

| Method | Path                     | Purpose                                              |
|--------|--------------------------|------------------------------------------------------|
| GET    | `/`                      | Dashboard: registered robots + recent activity       |
| GET    | `/robots/:name`          | Chat page for a robot                                 |
| POST   | `/robots/:name/stream`   | Run a task, stream events as SSE (`message`/`done`/`error`) |
| POST   | `/robots/:name/chat`     | Non-streaming fallback; returns rendered transcript HTML |

## Development

After checking out the repo, run `bin/setup` to install dependencies, then
`rake test`. The core (event model, activity log, sink, stream hook) is
pure-Ruby and unit-tested in isolation; the Sinatra app is covered with
`rack-test`.

The Sinatra stack is opt-in: `require "robot_lab/web"` loads only the core;
`require "robot_lab/web/app"` (or `RobotLab::Web.app`) pulls in Sinatra/Falcon/Slim.

## License

Available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
