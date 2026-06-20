# frozen_string_literal: true

module RobotLab
  module Web
    module Components
      # The HTML document shell: Tailwind (Play CDN) + the shared component
      # styles, the top nav, and a slot for the page component passed as +content+.
      class Layout < Phlex::HTML
        def initialize(csrf:, content:)
          @csrf = csrf
          @content = content
        end

        def view_template
          doctype
          html(lang: "en", class: "dark") do
            head do
              meta(charset: "utf-8")
              meta(name: "viewport", content: "width=device-width, initial-scale=1")
              meta(name: "csrf-token", content: @csrf)
              title { "robot_lab-web" }
              # Tailwind via the Play CDN (dev tool — fine for localhost).
              script(src: "https://cdn.tailwindcss.com")
              # Styles are Tailwind utilities composed with @apply so the server
              # components and the SSE client's JS-built nodes share one
              # definition (the message bubble is rendered by both Message and
              # chat.js).
              style(type: "text/tailwindcss") { raw(safe(STYLES)) }
            end
            body(class: "bg-zinc-950 text-zinc-200 font-sans text-[15px] leading-relaxed") do
              header(class: "flex items-center gap-3 px-5 py-3.5 border-b border-zinc-800") do
                span(class: "flex items-center gap-2 text-violet-400 font-bold tracking-wide") do
                  render PhlexIcons::Hero::CpuChip.new(class: "w-5 h-5")
                  plain "robot_lab-web"
                end
                a(href: "/", class: "text-indigo-400 no-underline hover:underline") { "Dashboard" }
              end
              main(class: "max-w-4xl mx-auto px-5 pt-6 pb-16") { render @content }
            end
          end
        end

        STYLES = <<~CSS
          @layer base {
            html { color-scheme: dark; }
            a    { @apply text-indigo-400 no-underline hover:underline; }
            h1   { @apply text-2xl font-semibold; }
            h2   { @apply text-xl font-semibold mt-8 mb-2; }
            pre  { @apply bg-zinc-900 border border-zinc-800 rounded-md p-3 text-sm overflow-x-auto; }
            input[type=text] { @apply flex-1 rounded-lg border border-zinc-700 bg-zinc-900 text-zinc-200 px-3.5 py-2.5 outline-none focus:border-indigo-500; }
            button { @apply rounded-lg bg-indigo-500 text-zinc-950 font-semibold px-4 py-2.5 cursor-pointer; }
            button:disabled { @apply opacity-50 cursor-default; }
          }
          @layer components {
            .robots   { @apply list-none p-0; }
            .robots li { @apply mb-2 rounded-lg border border-zinc-800 bg-zinc-900 px-3.5 py-2.5; }
            .activity { @apply list-none p-0; }
            .activity li { @apply py-1.5 border-b border-zinc-800/70 text-[13px] text-zinc-400; }
            .muted    { @apply text-zinc-500; }
            .transcript { @apply flex flex-col gap-2.5 min-h-[240px] py-2; }
            .composer { @apply flex gap-2 sticky bottom-0 bg-zinc-950 py-3; }
            .msg { @apply max-w-[92%] whitespace-pre-wrap break-words rounded-xl border border-zinc-800 px-3.5 py-2.5; }
            .msg.user { @apply self-end bg-indigo-950/50 border-indigo-800/60; }
            .msg.robot { @apply self-start bg-emerald-950/40 border-emerald-900/60; }
            .msg.tool_call, .msg.tool_result { @apply self-start bg-zinc-900 text-zinc-300 text-[13px] font-mono; }
            .msg.error { @apply self-start bg-rose-950/50 border-rose-900/60 text-rose-200; }
            .msg .role { @apply text-[11px] uppercase tracking-wider text-zinc-500 mb-1; }
          }
        CSS
      end
    end
  end
end
