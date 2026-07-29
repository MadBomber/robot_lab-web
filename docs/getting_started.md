# Getting Started

## Prerequisites

- Ruby 3.2+ (per the gemspec's `required_ruby_version`)
- `robot_lab` — a hard dependency; `robot_lab/web` requires it directly (see [How It Works — Core vs. Opt-In Web Stack](how_it_works.md#core-vs-opt-in-web-stack)), so load order relative to your own `require "robot_lab"` never matters
- A provider API key for whatever model your robots use (e.g. `ANTHROPIC_API_KEY`) — the console itself needs no credentials, but actually running a robot through it does

## Installation

```ruby
gem "robot_lab"
gem "robot_lab-web"
```

```sh
bundle install
```

## Writing a Boot File

A boot file just builds your robots and registers each one — the console reads this registry to list and drive them:

```ruby
# my_robots.rb
require "robot_lab"
require "robot_lab/web"

assistant = RobotLab.build(name: "assistant", system_prompt: "You are a concise, friendly assistant.")
RobotLab::Web.register(assistant)

# Register as many as you like:
# RobotLab::Web.register(RobotLab.build(name: "support", template: :support))
```

`register(robot, name: nil)` keys the robot by `name:` if given, otherwise by `robot.name` — see [API Reference](api_reference.md#registryregisterrobot-name-nil-string).

## Launching the Console

**Via the bundled executable** (Falcon, the default server):

```sh
robot_lab-web my_robots.rb                # http://127.0.0.1:9292
robot_lab-web --port 4567 my_robots.rb    # custom port
robot_lab-web --host 0.0.0.0 my_robots.rb # custom bind host
```

**Or via `config.ru`**, with any Rack server (the app itself is server-agnostic — `exe/robot_lab-web` picks Falcon specifically for its async/fiber reactor, but nothing about the Sinatra app requires it):

```sh
ROBOT_LAB_WEB_BOOT=my_robots.rb falcon serve -c config.ru
```

`ROBOT_LAB_WEB_BOOT` (or the boot file argument to the executable) is required by path before the app starts — `config.ru`/`exe/robot_lab-web` both check `File.exist?(boot)` and simply skip loading it if the path doesn't resolve, so a typo'd path silently produces a console with zero registered robots rather than an error.

Then open the dashboard, pick a robot, and start chatting.

## Running from a Source Checkout

If you're working inside a clone of `robot_lab-web` itself (rather than the installed gem), `exe/robot_lab-web` calls `require 'bundler/setup'` when it finds a `Gemfile` sitting beside it — this is what resolves the gem's own `lib` and its dependencies, including a local `robot_lab` path dependency during development (see `Gemfile.local`). Run it from the gem's own directory (or via `bundle exec`) so that path resolution works; an installed gem has no adjacent `Gemfile` and falls through to plain RubyGems resolution instead.

## Consuming the Stream from Ruby

The same path the web routes use is available directly — useful in tests, a script, or a custom front end that isn't the bundled Sinatra app:

```ruby
require "robot_lab"
require "robot_lab/web"

RobotLab::Web.run(assistant, "Hello") do |event|
  puts "#{event.role}: #{event.text}"
end
```

This doesn't touch Sinatra/Falcon/Phlex at all — see [How It Works](how_it_works.md#core-vs-opt-in-web-stack) for exactly what loading `"robot_lab/web"` alone gives you versus `"robot_lab/web/app"`.

## The Four Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Dashboard: registered robots + a recent-activity feed |
| `GET` | `/robots/:name` | Chat page for one robot |
| `POST` | `/robots/:name/stream` | Run a task, stream events as Server-Sent Events (`message`/`done`/`error` frames) |
| `POST` | `/robots/:name/chat` | Non-streaming fallback — runs to completion and returns rendered transcript HTML fragments (for HTMX `hx-swap="beforeend"`-style appending) |

See [How It Works](how_it_works.md#the-sse-wire-protocol) for the exact frame format and why the streaming route can't just be a plain `EventSource`.

## Development

```sh
bin/setup    # install dependencies
rake test    # run the test suite
```

The core (event model, activity log, sink, stream hook) is pure Ruby and unit-tested in isolation; the Sinatra app is covered with `rack-test`.
