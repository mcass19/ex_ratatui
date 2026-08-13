<p align="center">
  <a href="https://github.com/mcass19/ex_ratatui">
    <img src="https://raw.githubusercontent.com/mcass19/ex_ratatui/main/assets/logo_letters.png" alt="ExRatatui" width="480" />
  </a>
</p>

<p align="center">
  Elixir bindings for the Rust <a href="https://ratatui.rs">ratatui</a> terminal UI library, via <a href="https://github.com/rustler-beam/rustler">Rustler</a> NIFs.<br />
  Build rich terminal UIs in Elixir with ratatui's layout engine, widget library, and styling system together with the BEAM superpowers.
</p>

<p align="center">
  <a href="https://hex.pm/packages/ex_ratatui"><img src="https://img.shields.io/hexpm/v/ex_ratatui.svg" alt="Hex.pm" /></a>
  <a href="https://hexdocs.pm/ex_ratatui"><img src="https://img.shields.io/badge/hex-docs-blue" alt="Docs" /></a>
  <a href="https://github.com/mcass19/ex_ratatui/actions/workflows/ci.yml"><img src="https://github.com/mcass19/ex_ratatui/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="https://github.com/mcass19/ex_ratatui/blob/main/LICENSE"><img src="https://img.shields.io/hexpm/l/ex_ratatui.svg" alt="License" /></a>
</p>

---

## Features

- **25 built-in widgets** — Paragraph, Block, List, Table, Gauge, BarChart, Chart, Canvas, Calendar, Tabs, TextInput, Textarea, Markdown, Image, BigText, CodeBlock, Viewport3D, and more
- **Constraint-based layout** — percentages, lengths, ratios, min/max, and fill constraints, with flex alignment and spacing
- **Rich styling** — named, RGB, and 256-indexed colors, text modifiers, per-span rich text, and a semantic theme palette
- **Two runtimes** — LiveView-style callbacks or an Elm-style reducer with commands and subscriptions, both OTP-supervised
- **Transport-agnostic apps** — the same module serves a local terminal, SSH clients, or remote BEAM nodes over Erlang distribution
- **Non-terminal rendering** — expose the rendered cell buffer to Phoenix LiveView, embedded framebuffers, and screenshot tools
- **Images in the terminal** — PNG / JPEG / GIF / WebP rendered via Kitty, Sixel, iTerm2, or halfblocks, adapting to the terminal at hand
- **3D rendering** — software-rasterized or ray-traced scenes (`Viewport3D`) with meshes, lights, materials, a movable camera, and a scene-graph for articulated models, blitted into true-color cells
- **Syntax-highlighted code and big text** — `CodeBlock` with curated themes; oversized 8×8 pixel text for titles and banners
- **Full event handling** — non-blocking keyboard, mouse, resize, focus, and bracketed-paste events
- **Focus management** — a declarative focus ring with Tab cycling and mouse hit-testing for multi-panel apps
- **Custom widgets in pure Elixir** — compose primitives into reusable widgets via a protocol, no Rust required
- **First-class testing** — headless backend and event injection for CI-friendly assertions
- **Observability built in** — `:telemetry` events across runtime, render, and transports
- **Precompiled NIFs** — no Rust toolchain needed; event polling runs on the DirtyIo scheduler and never blocks the BEAM
- **Single-binary distribution** — ship a TUI as one native executable per OS/arch via [Burrito](https://github.com/burrito-elixir/burrito), no Erlang or Rust install needed on the target machine; `mix ex_ratatui.gen.burrito` scaffolds the wiring

## Installation

Add `ex_ratatui` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_ratatui, "~> 0.13"}
  ]
end
```

Then fetch and compile:

```sh
mix deps.get && mix compile
```

A precompiled NIF binary for the host platform is downloaded automatically. The native library itself is loaded lazily on first use, so compiling a project that depends on `ex_ratatui` does not require the NIF to be loaded into the compiler VM.

### Prerequisites

- Elixir 1.17+
- Erlang/OTP 26 – 29

Precompiled NIF binaries are available for Linux (x86_64, aarch64, armv6/hf, riscv64), macOS (x86_64, aarch64), and Windows (x86_64), covering NIF ABI versions 2.16 (OTP 26) and 2.17 (OTP 27/28) — no Rust toolchain needed. OTP 29 raised the ABI to 2.18; since the NIF ABI is backward compatible, OTP 29 loads the 2.17 binary and also needs no Rust toolchain. A native 2.18 build is pending `rustler_precompiled` support upstream.

On musl systems (Alpine, single-binary [Burrito](https://github.com/burrito-elixir/burrito) payloads, Nerves-style rootfs): the `*-unknown-linux-musl` artifacts published up to v0.11.2 dynamically link `libgcc_s.so.1`, which stock musl systems do not ship — `apk add libgcc` fixes the resulting relocation error. Artifacts from later releases embed the unwinder statically and depend on musl libc alone.

To compile from source instead, install the [Rust toolchain](https://rustup.rs/) and set:

```sh
export EX_RATATUI_BUILD=true
```

Or, without an env var, in your `config/config.exs`:

```elixir
config :rustler_precompiled, :force_build, ex_ratatui: true
```

The application config takes precedence over `EX_RATATUI_BUILD`, and `config :rustler_precompiled, force_build_all: true` takes precedence over both.

Either way, forcing a build also requires Rustler in the consuming project's dependencies — ex_ratatui declares `:rustler` as optional, and optional dependencies are not fetched transitively, so without it the build fails with `Rustler.Compiler is not available`:

```elixir
{:rustler, ">= 0.0.0"}
```

Forcing a build is also required when depending on a git tag instead of Hex (`{:ex_ratatui, github: "mcass19/ex_ratatui", tag: "..."}`): the checksum file for a release's precompiled artifacts can only be committed after the tag triggers their build, so each tag predates its own checksums and the precompiled path fails with `the precompiled NIF file does not exist in the checksum file`. The Hex package always carries the complete checksum file.

## Quick Start

```elixir
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph}

ExRatatui.run(fn terminal ->
  {w, h} = ExRatatui.terminal_size()

  paragraph = %Paragraph{
    text: "Hello from ExRatatui!\n\nPress any key to exit.",
    style: %Style{fg: :green, modifiers: [:bold]},
    alignment: :center,
    block: %Block{
      title: " Hello World ",
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: :cyan}
    }
  }

  ExRatatui.draw(terminal, [{paragraph, %Rect{x: 0, y: 0, width: w, height: h}}])

  # Wait for a keypress, then exit
  ExRatatui.poll_event(60_000)
end)
```

Try the [examples catalog](examples/README.md) for more — every widget has a focused, copyable demo, e.g. `mix run examples/basics/hello_world.exs`.

New here? The [Getting Started](guides/introduction/getting_started.md) guide builds a supervised todo app from `mix new` to a working TUI.

## Runtimes and Transports

ExRatatui offers two ways to structure a supervised app and several ways to serve it — every combination works, and switching transport doesn't change the app module.

- **Runtimes:** the [Callback Runtime](guides/runtimes/callback_runtime.md) (LiveView-style `mount`/`render`/`handle_event`, the default) and the [Reducer Runtime](guides/runtimes/reducer_runtime.md) (Elm-style single `update/2` with first-class commands and subscriptions). The callback guide has a [side-by-side comparison](guides/runtimes/callback_runtime.md#callback-or-reducer).
- **Transports:** local terminal (the default), [SSH](guides/transports/ssh_transport.md), [Erlang distribution](guides/transports/distributed_transport.md), [custom transports](guides/transports/custom_transports.md), and [non-terminal surfaces](guides/transports/cell_session.md). The [Transports guide](guides/transports/transports.md) has the canonical feature matrix.

## Guides

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/introduction/getting_started.md) | Walk-through from `mix new` to a supervised TUI — the place to start |
| [Building UIs](guides/core/building_uis.md) | Widgets, layout, styles, rich text, and events — everything for `render/2` |
| [Custom Widgets](guides/core/custom_widgets.md) | Compose primitives into reusable widgets via the `ExRatatui.Widget` protocol |
| [Images](guides/core/images.md) | Image rendering across terminals and transports — protocols, resizing, telemetry |
| [3D Rendering](guides/core/3d.md) | Lit 3D scenes with `Viewport3D` — meshes, camera, render modes, and pipelines |
| [Paste and Clipboard](guides/core/paste_and_clipboard.md) | Bracketed paste behaviour, batch-insert helpers, and an OSC 52 copy snippet |
| [Callback Runtime](guides/runtimes/callback_runtime.md) | OTP-supervised apps with `mount`, `render`, `handle_event`, and `handle_info` callbacks |
| [Reducer Runtime](guides/runtimes/reducer_runtime.md) | Elm-style apps with `init`, `update`, `subscriptions`, commands, and runtime inspection |
| [State Machine Patterns](guides/runtimes/state_machines.md) | Multi-screen apps, modals, and conditional UI without the tangle |
| [Transports](guides/transports/transports.md) | Canonical feature matrix — what works where across Local / Session / SSH / Distributed / CellSession |
| [Running TUIs over SSH](guides/transports/ssh_transport.md) | Serve any app as a remote TUI over SSH, standalone or under `nerves_ssh` |
| [Running TUIs over Erlang Distribution](guides/transports/distributed_transport.md) | Drive a TUI from a remote BEAM node with zero NIF on the app side |
| [Custom Transports](guides/transports/custom_transports.md) | Plug in a custom transport (TCP, Livebook, WebSocket) via the `ExRatatui.Transport` behaviour |
| [Rendering to Non-Terminal Surfaces](guides/transports/cell_session.md) | Use `ExRatatui.CellSession` to expose the rendered cell buffer to LiveView, framebuffers, screenshot tools, and other non-ANSI consumers |
| [Architecture](guides/internals/architecture.md) | The NIF bridge and the per-transport process trees |
| [Testing](guides/internals/testing.md) | Headless backend, `test_mode`, `inject_event`, and assertion patterns |
| [Debugging](guides/internals/debugging.md) | `Runtime.snapshot`, tracing, buffer inspection, and common errors |
| [Performance](guides/internals/performance.md) | Render-loop tuning, `render?: false`, large trees, async effects |
| [Telemetry](guides/internals/telemetry.md) | `:telemetry` events for runtime, render, transport, and session — logging, metrics, OpenTelemetry |
| [Packaging with Burrito](guides/packaging/packaging_with_burrito.md) | Ship a TUI as a single-file native binary per OS/arch via [Burrito](https://github.com/burrito-elixir/burrito) — no Erlang or Rust install required for end users |
| [Widgets Cheatsheet](guides/cheatsheets/widgets.cheatmd) | One-page reference with every struct and its key fields |

## How It Works

ExRatatui bridges Elixir and Rust through [Rustler](https://github.com/rustler-beam/rustler) NIFs: widget structs are encoded across the NIF boundary and decoded into ratatui types for rendering, while terminal events are polled on BEAM's DirtyIo scheduler so nothing blocks Elixir processes. Every transport builds on the same supervised `Server` process, with full session isolation per connected client.

The [Architecture guide](guides/internals/architecture.md) has the full picture — the NIF bridge and the per-transport process trees.

## Ecosystem

- [kino_ex_ratatui](https://github.com/mcass19/kino_ex_ratatui) — Run TUIs inside [Livebook](https://livebook.dev) notebooks.
- [phoenix_ex_ratatui](https://github.com/mcass19/phoenix_ex_ratatui) — Run TUIs in the browser within [Phoenix LiveView](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html).

## Built with ExRatatui

- [ash_tui](https://github.com/mcass19/ash_tui) — Interactive terminal explorer for [Ash](https://ash-hq.org) domains, resources, attributes, actions, and more.
- [bb_tui](https://github.com/mcass19/bb_tui) — Terminal-based dashboard for [Beam Bots](https://github.com/beam-bots) robots.
- [switchyard](https://github.com/nshkrdotcom/switchyard) — Full-featured reducer runtime workbench exercising command batching, async effects, subscription reconciliation, runtime snapshots, distributed attach, and row-scrolled WidgetList.
- [caudata](https://github.com/quaywin/caudata) — Zero-config multi-server log streamer aggregating real-time logs from remote Linux hosts over native SSH, with Docker/Systemd/Launchd discovery and live CPU, RAM, and disk metrics.
- [ex_athena](https://github.com/udin-io/ex_athena) — Provider-agnostic AI agent loop with a terminal chat TUI (via `mix athena.chat`), supporting Ollama, OpenAI-compatible, llama.cpp, and Anthropic backends.
- [beamcore](https://github.com/beamcore/agent) — Terminal coding agent where each instance is a distributed [OTP](https://www.erlang.org/) node, with in-VM code execution, persistent memory, mesh RPC, live runtime attachment, and multi-provider LLM support.
- [extop](https://github.com/z7ealth/extop) — Live Linux system monitor with real-time CPU, GPU, memory, disk, and network charts alongside a sortable, filterable process table with signal management.
- [phoenix_gen_api_tui](https://hex.pm/packages/phoenix_gen_api_tui) — Terminal-based explorer for [PhoenixGenApi](https://hex.pm/packages/phoenix_gen_api) applications, with runtime inspection of services, call flows, cluster topology, health, and rate limits — no database connection required.
- [nerves_ex_ratatui_example](https://github.com/mcass19/nerves_ex_ratatui_example) — Example [Nerves](https://nerves-project.org) project with two TUIs (system monitor and LED control) on embedded hardware, reachable over SSH subsystems and Erlang distribution.
- [phoenix_ex_ratatui_example](https://github.com/mcass19/phoenix_ex_ratatui_example) — Example [Phoenix](https://www.phoenixframework.org/) project with a TUI served over SSH and Erlang distribution alongside a public LiveView chat room, sharing PubSub between the browser and the terminal.
- ... yours? Open a PR! Plenty of ideas to explore in [awesome-ratatui](https://github.com/ratatui/awesome-ratatui).

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](https://github.com/mcass19/ex_ratatui/blob/main/CONTRIBUTING.md) for development setup and PR guidelines.

## Acknowledgements

ExRatatui is undeniably inspired by [ratatui](https://github.com/ratatui/ratatui). Having such a great terminal UI library in Rust was the motivation to bring the same experience to the Elixir world and combine the best of both worlds. Special thanks to the great community behind ratatui.

The ExRatatui logo adapts the ratatui logo designed by [Pavel Fomchenkov](https://github.com/nawok), with the Elixir drop and ex_ratatui wordmark added by [Malena Merlina](https://www.linkedin.com/in/malenamerlinadiez).

## License

MIT — see [LICENSE](https://github.com/mcass19/ex_ratatui/blob/main/LICENSE) for details.
