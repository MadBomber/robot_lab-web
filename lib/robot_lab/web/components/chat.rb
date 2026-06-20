# frozen_string_literal: true

module RobotLab
  module Web
    module Components
      # The chat page for one robot: transcript, composer, and the small vanilla
      # SSE client that streams a run token-by-token into the transcript.
      class Chat < Phlex::HTML
        def initialize(name:)
          @name = name
        end

        def view_template
          h1(class: "flex items-center gap-2") do
            a(href: "/", class: "inline-flex") do
              render PhlexIcons::Hero::ArrowLeft.new(class: "w-6 h-6")
            end
            plain @name
          end

          div(id: "transcript", class: "transcript")

          form(id: "composer", class: "composer", data: { stream_url: "/robots/#{@name}/stream" }) do
            input(
              type: "text", name: "message", id: "message",
              placeholder: "Message #{@name}…", autocomplete: "off", autofocus: true
            )
            button(type: "submit", id: "send", class: "flex items-center gap-1.5") do
              plain "Send"
              render PhlexIcons::Hero::PaperAirplane.new(class: "w-4 h-4")
            end
          end

          script { raw(safe(CLIENT_JS)) }
        end

        # The robot name only reaches JS via the form's data-stream-url attribute
        # (set above), so this script needs no server interpolation.
        CLIENT_JS = <<~'JS'
          const csrf = document.querySelector('meta[name="csrf-token"]').content;
          const streamUrl = document.getElementById('composer').dataset.streamUrl;
          const transcript = document.getElementById('transcript');
          const form = document.getElementById('composer');
          const input = document.getElementById('message');
          const send = document.getElementById('send');

          function el(role, html) {
            const d = document.createElement('div');
            d.className = 'msg ' + role;
            d.innerHTML = html;
            transcript.appendChild(d);
            transcript.scrollTop = transcript.scrollHeight;
            return d;
          }
          const esc = (s) => String(s ?? '').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
          function header(role, robot) {
            return '<div class="role">' + esc(role) + (robot ? ' · ' + esc(robot) : '') + '</div>';
          }

          // The robot bubble currently being filled by streamed :delta events.
          let streaming = null;

          function appendDelta(ev) {
            if (!streaming) {
              const bubble = el('robot', header('robot', ev.robot_name) + '<span class="body"></span>');
              streaming = bubble.querySelector('.body');
            }
            streaming.textContent += ev.content ?? '';
            transcript.scrollTop = transcript.scrollHeight;
          }

          function renderEvent(ev) {
            const c = ev.content || {};
            if (ev.role === 'delta') { appendDelta(ev); return; }
            if (ev.role === 'user') return; // already shown optimistically

            if (ev.role === 'robot' && streaming) {
              streaming.textContent = typeof ev.content === 'string' ? ev.content : streaming.textContent;
              streaming = null;
              return;
            }
            streaming = null;

            let body;
            switch (ev.role) {
              case 'tool_call':   body = esc(c.name) + '(' + esc(JSON.stringify(c.args)) + ')'; break;
              case 'tool_result': body = c.error ? esc(c.name) + ' → error: ' + esc(c.error)
                                                  : esc(c.name) + ' → ' + esc(JSON.stringify(c.result)); break;
              case 'error':       body = esc(c.message || ev.content); break;
              default:            body = esc(typeof ev.content === 'string' ? ev.content : JSON.stringify(ev.content));
            }
            el(ev.role, header(ev.role, ev.robot_name) + body);
          }

          async function streamRun(message) {
            const res = await fetch(streamUrl, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-CSRF-Token': csrf },
              body: 'message=' + encodeURIComponent(message)
            });
            const reader = res.body.getReader();
            const decoder = new TextDecoder();
            let buf = '';
            while (true) {
              const { value, done } = await reader.read();
              if (done) break;
              buf += decoder.decode(value, { stream: true });
              const frames = buf.split('\n\n');
              buf = frames.pop();
              for (const frame of frames) {
                let type = 'message', data = '';
                for (const line of frame.split('\n')) {
                  if (line.startsWith('event:')) type = line.slice(6).trim();
                  else if (line.startsWith('data:')) data += line.slice(5).trim();
                }
                if (!data) continue;
                const payload = JSON.parse(data);
                if (type === 'message') renderEvent(payload);
                else if (type === 'error') el('error', header('error') + esc(payload.message));
              }
            }
          }

          form.addEventListener('submit', async (e) => {
            e.preventDefault();
            const message = input.value.trim();
            if (!message) return;
            streaming = null;
            el('user', header('user') + esc(message));
            input.value = '';
            input.disabled = send.disabled = true;
            try { await streamRun(message); }
            catch (err) { el('error', header('error') + esc(err.message)); }
            finally { input.disabled = send.disabled = false; input.focus(); }
          });
        JS
      end
    end
  end
end
