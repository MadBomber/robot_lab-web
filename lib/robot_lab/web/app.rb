# frozen_string_literal: true

require 'openssl'
require 'securerandom'
require 'json'
require 'sinatra/base'
require 'phlex-sinatra'
require 'phlex-icons-hero'
require 'rack/utils'

require_relative '../web'
require_relative 'components/layout'
require_relative 'components/dashboard'
require_relative 'components/chat'
require_relative 'components/message'
require_relative 'components/error_page'

module RobotLab
  module Web
    # Sinatra console for driving robot_lab robots from the browser and
    # streaming each run over Server-Sent Events.
    #
    # This is a DEVELOPER TOOL, unauthenticated by default — run it on
    # localhost or a trusted network. The security touches below (CSRF with
    # constant-time compare, hashed session secret, cookie flags, production
    # boot guard) harden the surface but do not make it safe to expose publicly.
    class App < Sinatra::Base
      # phlex-sinatra registers its `phlex` helper on the classic
      # Sinatra::Application; a modular Sinatra::Base app must include it.
      helpers Phlex::Sinatra

      # Stable session secret. Uses SESSION_SECRET when set; otherwise persists a
      # per-user random secret so it survives restarts. A fresh random secret on
      # every boot would invalidate existing session cookies ("HMAC is invalid").
      def self.session_secret_source
        ENV['SESSION_SECRET'] || persisted_dev_secret
      end

      def self.persisted_dev_secret
        path     = File.join(Dir.home, '.config', 'robot_lab', 'web_session_secret')
        existing = File.read(path).strip if File.exist?(path)
        return existing if existing && !existing.empty?

        require 'fileutils'
        FileUtils.mkdir_p(File.dirname(path))
        SecureRandom.hex(64).tap do |secret|
          File.write(path, secret)
          File.chmod(0o600, path)
        end
      end

      configure do
        # Sinatra 4 / rack-protection enable Host authorization by default,
        # which 403s any Host header not explicitly permitted. This dev tool is
        # reached via localhost or whatever host the operator binds — permit all.
        set :host_authorization, { permitted_hosts: [] }
        set :sessions, httponly: true, same_site: :lax, secure: production?

        # Hash to a 64-hex key — the encrypted-cookie store errors on short/odd
        # secrets; hashing makes any value work deterministically.
        set :session_secret, OpenSSL::Digest::SHA256.hexdigest(session_secret_source)
      end

      configure :production do
        unless ENV['SESSION_SECRET']
          raise 'SESSION_SECRET must be set in production; a per-process random ' \
                'fallback breaks sessions and CSRF across restarts and workers.'
        end
      end

      CSRF_SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

      before do
        session[:csrf] ||= SecureRandom.hex(32)
        next if CSRF_SAFE_METHODS.include?(request.request_method)

        provided = params['authenticity_token'] || request.env['HTTP_X_CSRF_TOKEN']
        halt 403, 'Forbidden: invalid CSRF token' unless provided &&
                                                         Rack::Utils.secure_compare(provided, session[:csrf])
      end

      helpers do
        def csrf_token
          session[:csrf]
        end

        # Render a page component wrapped in the Layout (HTML doc shell).
        def page(content)
          phlex Components::Layout.new(csrf: csrf_token, content: content)
        end

        def robot_or_not_found(name)
          Registry.fetch(name) ||
            halt(404, page(Components::ErrorPage.new(message: "No robot named #{name.inspect}")))
        end

        # Render one transcript message (Event) to an HTML fragment.
        def message_html(event)
          Components::Message.new(event: event).call
        end
      end

      # --- Dashboard -------------------------------------------------------

      get '/' do
        page Components::Dashboard.new(robots: Registry.names, activity: ActivityLog.recent(15))
      end

      get '/robots/:name' do
        robot_or_not_found(params[:name])
        page Components::Chat.new(name: params[:name])
      end

      # --- Streaming run (SSE) ---------------------------------------------
      #
      # Each lifecycle Event is pushed the instant it happens; the run ends with
      # a `done` frame (or `error`). Consume with fetch() streaming — the route
      # is CSRF-protected, so EventSource (GET-only, no headers) can't be used.
      post '/robots/:name/stream' do
        robot = robot_or_not_found(params[:name])
        message = params['message'].to_s

        content_type 'text/event-stream'
        headers 'Cache-Control' => 'no-cache', 'X-Accel-Buffering' => 'no'

        stream do |out|
          write_sse = ->(type, data) { out << "event: #{type}\ndata: #{JSON.generate(data)}\n\n" }

          if message.empty?
            write_sse.call('error', { message: "Missing 'message'." })
          else
            begin
              result = RobotLab::Web.run(robot, message) { |event| write_sse.call('message', event.to_h) }
              write_sse.call('done', { reply: final_text(result) })
            rescue StandardError => e
              write_sse.call('error', { message: e.message })
            end
          end
        end
      end

      # --- Non-streaming fallback (HTMX append) — resilient default -------
      #
      # Works without JS streaming: run to completion, collect events, return
      # the rendered transcript fragments for `hx-swap="beforeend"`.
      post '/robots/:name/chat' do
        robot = robot_or_not_found(params[:name])
        message = params['message'].to_s
        halt 400, 'Missing message' if message.empty?

        events = []
        RobotLab::Web.run(robot, message) { |event| events << event }
        content_type :html
        # Drop :delta events — the final :robot event already carries the full
        # reply, so the non-streaming transcript shows it once.
        events.reject { |event| event.role == :delta }
              .map { |event| message_html(event) }.join("\n")
      end

      helpers do
        def final_text(result)
          return result.reply if result.respond_to?(:reply)
          return result.last_text_content if result.respond_to?(:last_text_content)

          result.to_s
        end
      end
    end
  end
end
