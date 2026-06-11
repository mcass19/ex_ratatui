# ExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/ex_ratatui.svg)](https://hex.pm/packages/ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/ex_ratatui)
[![CI](https://github.com/mcass19/ex_ratatui/actions/workflows/ci.yml/badge.svg)](https://github.com/mcass19/ex_ratatui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/ex_ratatui.svg)](https://github.com/mcass19/ex_ratatui/blob/main/LICENSE)

Elixir bindings for the Rust [ratatui](https://ratatui.rs) terminal UI library, via [Rustler](https://github.com/rustler-beam/rustler) NIFs.

Build rich terminal UIs in Elixir with ratatui's layout engine, widget library, and styling system together with the BEAM superpowers.

![ExRatatui Demo](https://raw.githubusercontent.com/mcass19/ex_ratatui/main/assets/demo.gif)

## Features

- 24 built-in widgets (and counting!): Paragraph, Block, List, Table, Gauge, LineGauge, BarChart, Sparkline, Calendar, Canvas, Chart, Tabs, Scrollbar, Checkbox, TextInput, Clear, Markdown, Textarea, Throbber, Popup, WidgetList, **Image**, **BigText**, **CodeBlock**
- **Image rendering** via [ratatui-image](https://github.com/ratatui/ratatui-image): PNG / JPEG / GIF / WebP / BMP, with Kitty / Sixel / iTerm2 / halfblocks protocols. Same model code adapts to the terminal at hand — pixel-perfect Kitty graphics locally, halfblocks fallback over SSH or in Livebook. See the [Images guide](guides/core/images.md).
- **Oversized 8×8 pixel text** via [tui-big-text](https://github.com/ratatui/tui-widgets/tree/main/tui-big-text): drop-in `BigText` widget for slide titles, splash screens, and end-of-game banners. Eight `pixel_size` densities from `:full` (one cell per pixel) to `:octant` (1 row × half cols).
- **Syntax-highlighted code** via [syntect](https://github.com/trishume/syntect): drop-in `CodeBlock` widget with seven curated themes, optional line-number gutter, and highlightable line ranges. `ExRatatui.CodeBlock.highlight/3` exposes the raw `[%Line{}]` data for users composing their own diff viewers / inspectors / pretty-printers.
- Constraint-based layout engine: percentage, length, min, max, ratio, and `{:fill, weight}` for growable panels; `Layout.split/4` accepts `:flex` (start/center/end/space_between/space_around) and `:spacing` opts for centered popups, end-aligned status bars, and segment gutters
- Non-blocking keyboard, mouse, resize, paste, and focus event polling — mouse capture, focus reporting, and bracketed paste exposed via `ExRatatui.run(fun, mouse_capture: true, focus_events: true)`. Bracketed paste lands as a single `%Event.Paste{}` instead of being shredded across keystrokes; `text_input_insert_str/2` and `textarea_insert_str/2` consume the payload in one NIF call
- OTP-supervised TUI apps: via `ExRatatui.App` behaviour with LiveView-inspired callbacks
- Reducer runtime: for command/subscription driven apps via `use ExRatatui.App, runtime: :reducer`
- Built-in SSH transport: serve any `ExRatatui.App` as a remote TUI, standalone or under `nerves_ssh`
- Erlang distribution transport: attach to a remote TUI over Erlang distribution with zero NIF on the app node
- Non-terminal rendering via `ExRatatui.CellSession`: expose the rendered cell buffer (snapshots and diffs) for Phoenix LiveView, embedded framebuffers, screenshot tools, and other consumers that don't speak ANSI
- Full color support: named, RGB, and 256-color indexed
- Text modifiers: bold, italic, underlined, and more
- Rich text on text-bearing widget fields (`Paragraph.text`, `List.items`, `Table` cells, `Tabs.titles`, `Block.title`): per-span colors and modifiers via `ExRatatui.Text.Span`/`Line`
- Multi-title blocks: top + bottom titles, per-title alignment, default styles — model patterns like `filename │ [3/12]` headers or bottom status bars in one struct
- Custom widgets in pure Elixir via the `ExRatatui.Widget` protocol: compose primitives into reusable composite widgets without touching Rust
- **Focus management** for multi-panel apps via `ExRatatui.Focus`: declare a ring of focusable IDs, cycle with Tab/Shift+Tab, register hit-test regions for `Focus.handle_mouse/2` so left-clicks focus the panel under the cursor (with the event passing through so widgets can still react), dispatch keystrokes to the active widget
- **Theming**: `ExRatatui.Theme` palette struct with eleven semantic slots (`:primary`, `:accent`, `:border`, `:border_focused`, `:surface`, `:text`, `:success`, `:warning`, `:danger`, …); `default/0` and `light/0` constructors plus `border_style/2`, `text_style/2`, `selection_style/1` helpers. Pure data — apps thread it through render code without globals
- Headless test backend for CI-friendly rendering verification
- Precompiled NIF binaries: no Rust toolchain needed
- Runs on BEAM's DirtyIo scheduler: never blocks your processes

## Examples

| Example | Run | Description |
|---------|-----|-------------|
| `hello_world.exs` | `mix run examples/basics/hello_world.exs` | Minimal paragraph display |
| `counter_app.exs` | `mix run examples/basics/counter_app.exs` | Counter using `ExRatatui.App` behaviour |

The full catalog (plus SSH and Erlang-distribution one-liners) lives in [`examples/README.md`](examples/README.md).

## Ecosystem

- [kino_ex_ratatui](https://github.com/mcass19/kino_ex_ratatui) — Run TUIs inside [Livebook](https://livebook.dev) notebooks.
- [phoenix_ex_ratatui](https://github.com/mcass19/phoenix_ex_ratatui) — Run TUIs in the browser within [Phoenix LiveView](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html).

## Built with ExRatatui

- [ash_tui](https://github.com/mcass19/ash_tui) — Interactive terminal explorer for [Ash](https://ash-hq.org) domains, resources, attributes, actions, and more.
- [bb_tui](https://github.com/mcass19/bb_tui) — Terminal-based dashboard for [Beam Bots](https://github.com/beam-bots) robots.
- [switchyard](https://github.com/nshkrdotcom/switchyard) — Full-featured reducer runtime workbench exercising command batching, async effects, subscription reconciliation, runtime snapshots, distributed attach, and row-scrolled WidgetList.
- [nerves_ex_ratatui_example](https://github.com/mcass19/nerves_ex_ratatui_example) — Example [Nerves](https://nerves-project.org) project with two TUIs (system monitor and LED control) on embedded hardware, reachable over SSH subsystems and Erlang distribution.
- [phoenix_ex_ratatui_example](https://github.com/mcass19/phoenix_ex_ratatui_example) — Example [Phoenix](https://www.phoenixframework.org/) project with a TUI served over SSH and Erlang distribution alongside a public LiveView chat room, sharing PubSub between the browser and the terminal.
- ... yours? Open a PR! Plenty of ideas to explore in [awesome-ratatui](https://github.com/ratatui/awesome-ratatui).

## Installation

Add `ex_ratatui` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_ratatui, "~> 0.10"}
  ]
end
```

Then fetch and compile:

```sh
mix deps.get && mix compile
```

A precompiled NIF binary for your platform will be downloaded automatically. The native library itself is loaded lazily on first use, so compiling a project that depends on `ex_ratatui` does not require the NIF to be loaded into the compiler VM.

### Prerequisites

- Elixir 1.17+

Precompiled NIF binaries are available for Linux (x86_64, aarch64, armv6/hf, riscv64), macOS (x86_64, aarch64), and Windows (x86_64). No Rust toolchain needed.

To compile from source instead, install the [Rust toolchain](https://rustup.rs/) and set:

```sh
export EX_RATATUI_BUILD=true
```

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

Try the [examples](examples/README.md) for more, e.g. `mix run examples/basics/hello_world.exs`.

New here? The [Getting Started](guides/introduction/getting_started.md) guide builds a supervised todo app from `mix new` to a working TUI.

## Choosing a Runtime

ExRatatui offers two runtime modes for supervised apps. Both are transport-agnostic — the same module works over local terminal, SSH, or Erlang distribution without changes.

| | Callback Runtime | Reducer Runtime |
|---|---|---|
| Opt-in | `use ExRatatui.App` (default) | `use ExRatatui.App, runtime: :reducer` |
| Entry point | `mount/1` | `init/1` |
| Events | `handle_event/2` + `handle_info/2` | Single `update/2` receives `{:event, _}` and `{:info, _}` |
| Side effects | Direct (send, spawn, etc.) | First-class `Command` primitives (message, send_after, async, batch) |
| Timers | Manual `Process.send_after/3` | Declarative `Subscription` with auto-reconciliation |
| Tracing | Not built-in | Built-in via `ExRatatui.Runtime` |
| Best for | Straightforward interactive TUIs | Apps with async I/O, structured effects, or complex state machines |

## Choosing a Transport

All transports serve the same `ExRatatui.App` module — switch by changing a single option.

| | Local (default) | SSH | Erlang Distribution |
|---|---|---|---|
| Opt-in | Automatic | `transport: :ssh` | `ExRatatui.Distributed.attach/3` |
| NIF required on | App node | App node (daemon) | Client node only |
| Multi-client | No (one terminal) | Yes (isolated per connection) | Yes (isolated per connection) |
| Auth | N/A | Password, public key, or custom | Erlang cookie |
| Best for | Local dev, Nerves console | Remote admin TUIs, Phoenix SSH | Headless nodes, cross-architecture |
| Session isolation | N/A | Full (each client gets own state) | Full (each client gets own state) |
| Network | N/A | TCP (SSH protocol) | Erlang distribution protocol |

## Guides

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/introduction/getting_started.md) | Walk-through from `mix new` to a supervised TUI — the place to start if you're new |
| [Building UIs](guides/core/building_uis.md) | Widgets, layout, styles, rich text, and events — everything for `render/2` |
| [Callback Runtime](guides/runtimes/callback_runtime.md) | OTP-supervised apps with `mount`, `render`, `handle_event`, and `handle_info` callbacks |
| [Reducer Runtime](guides/runtimes/reducer_runtime.md) | Elm-style apps with `init`, `update`, `subscriptions`, commands, and runtime inspection |
| [Custom Widgets](guides/core/custom_widgets.md) | Compose primitives into reusable widgets via the `ExRatatui.Widget` protocol |
| [State Machine Patterns](guides/runtimes/state_machines.md) | Multi-screen apps, modals, and conditional UI without the tangle |
| [Testing](guides/internals/testing.md) | Headless backend, `test_mode`, `inject_event`, and assertion patterns |
| [Debugging](guides/internals/debugging.md) | `Runtime.snapshot`, tracing, buffer inspection, and common errors |
| [Performance](guides/internals/performance.md) | Render-loop tuning, `render?: false`, large trees, async effects |
| [Telemetry](guides/internals/telemetry.md) | `:telemetry` events for runtime, render, transport, and session — logging, metrics, OpenTelemetry |
| [Transports](guides/transports/transports.md) | Canonical feature matrix — what works where across Local / Session / SSH / Distributed / CellSession |
| [Running TUIs over SSH](guides/transports/ssh_transport.md) | Serve any app as a remote TUI over SSH, standalone or under `nerves_ssh` |
| [Running TUIs over Erlang Distribution](guides/transports/distributed_transport.md) | Drive a TUI from a remote BEAM node with zero NIF on the app side |
| [Custom Transports](guides/transports/custom_transports.md) | Plug in your own transport (TCP, Livebook, WebSocket) via the `ExRatatui.Transport` behaviour |
| [Rendering to Non-Terminal Surfaces](guides/transports/cell_session.md) | Use `ExRatatui.CellSession` to expose the rendered cell buffer to LiveView, framebuffers, screenshot tools, and other non-ANSI consumers |
| [Paste and Clipboard](guides/core/paste_and_clipboard.md) | Bracketed paste behaviour, `text_input_insert_str`/`textarea_insert_str` helpers, and an OSC 52 copy snippet |
| [Widgets Cheatsheet](guides/cheatsheets/widgets.cheatmd) | One-page reference with every struct and its key fields |

## How It Works

ExRatatui bridges Elixir and Rust through [Rustler](https://github.com/rustler-beam/rustler) NIFs (Native Implemented Functions):

```
Elixir structs -> encode to maps -> Rust NIF -> decode to ratatui types -> render to terminal
Terminal events -> Rust NIF (DirtyIo) -> encode to tuples -> Elixir Event structs
```

- **Rendering:** Elixir widget structs are encoded as string-keyed maps, passed across the NIF boundary, and decoded into ratatui widget types for rendering.
- **Events:** The `poll_event` NIF runs on BEAM's DirtyIo scheduler, so event polling never blocks normal Elixir processes.
- **Terminal state:** Each process holds its own terminal reference via Rust ResourceArc, supporting two backends — a real crossterm terminal and a headless test backend for CI. The terminal is automatically restored when the reference is garbage collected.
- **Layout:** Ratatui's constraint-based layout engine is exposed directly, computing split rectangles on the Rust side and returning them as Elixir tuples.

Precompiled binaries are provided via [rustler_precompiled](https://github.com/philss/rustler_precompiled) so users don't need the Rust toolchain.

### Process Architecture

Each transport builds on the same internal `Server`, which owns the render loop and dispatches to your `ExRatatui.App` callbacks:

```
Local transport:
  Supervisor
  └── Server (GenServer)
        ├── owns terminal reference (NIF)
        ├── polls events on DirtyIo scheduler
        └── calls your mount/render/handle_event

SSH transport:
  Supervisor
  └── SSH.Daemon (GenServer, wraps :ssh.daemon)
        └── per client:
              SSH channel (:ssh_server_channel)
              ├── owns Session (in-memory terminal)
              ├── parses ANSI input → events
              └── Server (GenServer)
                    └── calls your mount/render/handle_event

Distributed transport:
  App node                              Client node
  ├── Distributed.Listener              └── Distributed.Client (GenServer)
  │   └── DynamicSupervisor                   ├── owns terminal reference (NIF)
  │       └── per client:                     ├── polls events locally
  │             Server (GenServer)            └── sends events → Server
  │             └── sends widgets → Client          receives widgets ← Server
  └── No NIF needed here
```

All transports provide full session isolation — each connected client gets its own `Server` process with independent state.

For writing tests see the [Testing](guides/internals/testing.md) guide; for runtime introspection and common errors see [Debugging](guides/internals/debugging.md).

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](https://github.com/mcass19/ex_ratatui/blob/main/CONTRIBUTING.md) for development setup and PR guidelines.

## License

MIT — see [LICENSE](https://github.com/mcass19/ex_ratatui/blob/main/LICENSE) for details.
