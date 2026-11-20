# Security

## The Posture, Stated Plainly

`robot_lab-web` is a **developer tool**, unauthenticated by default. There is no login, no user model, no access control of any kind on any route. Everything below hardens specific, real attack surfaces (CSRF, session-cookie theft, an accidentally-insecure production boot), but **none of it adds authentication** — and one default protection, Host-header authorization, is deliberately switched *off* (see [Host Authorization](#host-authorization)). Run this on `localhost` or a network you already trust; do not expose it to the public internet or to untrusted users on a shared network, regardless of how hardened the pieces below are individually.

## CSRF Protection

Every non-safe request (anything but `GET`/`HEAD`/`OPTIONS`) must carry a valid CSRF token, checked with a **constant-time comparison** (`Rack::Utils.secure_compare`) specifically to avoid a timing side-channel that could otherwise leak the correct token one byte at a time:

```ruby
before do
  session[:csrf] ||= SecureRandom.hex(32)
  next if CSRF_SAFE_METHODS.include?(request.request_method)

  provided = params['authenticity_token'] || request.env['HTTP_X_CSRF_TOKEN']
  halt 403, 'Forbidden: invalid CSRF token' unless provided.is_a?(String) && Rack::Utils.secure_compare(provided, session[:csrf])
end
```

A missing token, a wrong token, and a token that isn't a plain String (e.g. `authenticity_token[]=...`, which parses to an Array) are all rejected the same way, with `403`.

The token is accepted from either a request parameter named `authenticity_token` (read via `params`, so a form field or a query-string parameter both count) or a request header (`X-CSRF-Token`) — the latter is what the streaming chat client actually uses, since its request body is a URL-encoded `message=...` string, not a form submission carrying a hidden field. The page embeds the token in a `<meta name="csrf-token">` tag; the client JS reads it from there.

**This is also why the streaming route can't be a plain browser `EventSource`** — `EventSource` is GET-only and can't attach custom headers, so there'd be no way to present a CSRF token on that connection at all. See [How It Works — The SSE Wire Protocol](how_it_works.md#the-sse-wire-protocol) for the `fetch()`-based client this constraint leads to instead.

## Session Secret Persistence

Sinatra's encrypted cookie session store needs a stable secret — if the secret changes between requests, every existing session cookie becomes invalid (Sinatra's own "HMAC is invalid" error) and users get silently logged out (or, here, lose their CSRF token) on every restart. `App.session_secret_source` resolves the secret in priority order:

1. `ENV['SESSION_SECRET']`, if set
2. A **persisted** per-user random secret, generated once and written to `~/.config/robot_lab/web_session_secret` (mode `0600`) — read back on every subsequent boot instead of regenerating

```ruby
def self.persisted_dev_secret
  path = File.join(Dir.home, '.config', 'robot_lab', 'web_session_secret')
  existing = File.read(path).strip if File.exist?(path)
  return existing if existing && !existing.empty?

  require 'fileutils'
  FileUtils.mkdir_p(File.dirname(path))
  SecureRandom.hex(64).tap { |secret| File.write(path, secret, perm: 0o600); File.chmod(0o600, path) }
end
```

The resolved secret is then **hashed** (`OpenSSL::Digest::SHA256.hexdigest(...)`) before being handed to Sinatra as `session_secret` — Sinatra's encrypted-cookie store errors on a secret that's too short or an odd length, and hashing to a fixed 64-hex-char digest makes *any* input value (a short `SESSION_SECRET`, an oddly-sized one) work deterministically, without validating the input's shape yourself.

## Cookie Flags

```ruby
set :sessions, httponly: true, same_site: :lax, secure: production?
```

`httponly: true` — the session cookie is inaccessible to JavaScript (mitigates cookie theft via an XSS bug). `same_site: :lax` — the cookie isn't sent on most cross-site requests (mitigates CSRF further, on top of the explicit token check above). `secure: production?` — the cookie is marked HTTPS-only when running in a Sinatra `production` environment; left off in development, where a local Falcon instance typically isn't behind TLS at all. The flip side: in `production` over plain HTTP the session cookie is never set, so no CSRF token survives between requests and every `POST` is rejected with `403` — a production-mode console has to be served over HTTPS.

## Production Boot Guard

```ruby
configure :production do
  unless ENV['SESSION_SECRET']
    raise 'SESSION_SECRET must be set in production; the per-user persisted ' \
          'fallback secret differs across hosts, containers and users.'
  end
end
```

In a Sinatra `production` environment specifically (`APP_ENV` or `RACK_ENV` set to `production` when `robot_lab/web/app` is loaded), the persisted-random-secret fallback is refused — the app raises at boot rather than starting with a secret that lives in one user's home directory on one machine, and so would differ across hosts, containers, or users and break sessions/CSRF between them. The guard runs before the secret is resolved, so in production the fallback file is neither read nor created. This forces an explicit `SESSION_SECRET` in that one environment; development and test both still get the persisted-file fallback.

## Host Authorization

```ruby
set :host_authorization, { permitted_hosts: [] }
```

Sinatra 4.1+ (via `rack-protection`) ships Host-header authorization — a real protection against DNS-rebinding-style attacks in a typical web app. Its stock default only restricts the `development` environment, where requests are 403'd unless the `Host` is `localhost`, a `.localhost` or `.test` name, or an IP-address literal; in every other environment the stock default already permits all hosts. This console explicitly disables the check in every environment (`permitted_hosts: []` means "permit all") because, as a developer tool, it's reached via whatever host the operator chooses to bind (`localhost`, a LAN IP, a hostname on a private network) and there's no fixed "correct" host to allowlist ahead of time. This is a deliberate trade-off specific to this tool's use case, not an oversight — but it does mean Host-header-based attacks that this default would otherwise have blocked are back in play, which is one more reason this console belongs on a trusted network only.

## What This Doesn't Protect Against

To be explicit about the boundary: none of the above prevents **any** visitor who can reach the console's port from listing robots, reading recent activity, or driving a full chat run against any registered robot (including whatever tools that robot has access to). If a robot registered here has a tool that can read files, run shell commands, or call external APIs with real credentials, anyone who can reach this console can exercise all of that. Treat the console's network reachability itself as the actual access-control boundary, not anything documented above.
