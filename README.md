# ExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/ex_ratatui.svg)](https://hex.pm/packages/ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/ex_ratatui)
[![CI](https://github.com/mcass19/ex_ratatui/actions/workflows/ci.yml/badge.svg)](https://github.com/mcass19/ex_ratatui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/ex_ratatui.svg)](https://github.com/mcass19/ex_ratatui/blob/main/LICENSE)

Elixir bindings for the Rust [ratatui](https://ratatui.rs) terminal UI library, via [Rustler](https://github.com/rustler-beam/rustler) NIFs.

Build rich terminal UIs in Elixir with ratatui's layout engine, widget library, and styling system without blocking the BEAM.

![ExRatatui Demo](https://raw.githubusercontent.com/mcass19/ex_ratatui/main/assets/demo.gif)

## Features

- 16 built-in widgets (and counting!): Paragraph, Block, List, Table, Gauge, LineGauge, Tabs, Scrollbar, Checkbox, TextInput, Clear, Markdown, Textarea, Throbber, Popup, WidgetList
- Constraint-based layout engine (percentage, length, min, max, ratio)
- Non-blocking keyboard, mouse, and resize event polling
- **OTP-supervised TUI apps** via `ExRatatui.App` behaviour with LiveView-inspired callbacks
- **Reducer runtime** for command/subscription driven apps via `use ExRatatui.App, runtime: :reducer`
- **Built-in SSH transport**: serve any `ExRatatui.App` as a remote TUI, standalone or under `nerves_ssh`
- **Erlang distribution transport**: attach to a remote TUI over Erlang distribution with zero NIF on the app node
- Full color support: named, RGB, and 256-color indexed
- Text modifiers: bold, italic, underlined, and more
- **Rich text** on text-bearing widget fields (`Paragraph.text`, `List.items`, `Table` cells, `Tabs.titles`, `Block.title`): per-span colors and modifiers via `ExRatatui.Text.Span`/`Line`
- **Custom widgets in pure Elixir** via the `ExRatatui.Widget` protocol: compose primitives into reusable composite widgets without touching Rust
- **Focus management** for multi-panel apps via `ExRatatui.Focus`: declare a ring of focusable IDs, cycle with Tab/Shift+Tab, dispatch keystrokes to the active widget
- Headless test backend for CI-friendly rendering verification
- Precompiled NIF binaries: no Rust toolchain needed
- Runs on BEAM's DirtyIo scheduler: never blocks your processes

## Examples

| Example | Run | Description |
|---------|-----|-------------|
| `hello_world.exs` | `mix run examples/hello_world.exs` | Minimal paragraph display |
| `counter.exs` | `mix run examples/counter.exs` | Interactive counter with key events |
| `counter_app.exs` | `mix run examples/counter_app.exs` | Counter using `ExRatatui.App` behaviour |
| `reducer_counter_app.exs` | `mix run examples/reducer_counter_app.exs` | Counter using the reducer runtime with subscriptions |
| `system_monitor.exs` | `mix run examples/system_monitor.exs` | Linux system dashboard: CPU, memory, disk, network, BEAM stats (Linux/Nerves only). **Also runs over SSH and Erlang distribution** (see below). |
| `widget_showcase.exs` | `mix run examples/widget_showcase.exs` | Interactive showcase: tabs, progress bars, checkboxes, text input, scrollable logs |
| `task_manager.exs` | `mix run examples/task_manager.exs` | Full task manager with tabs, table, scrollbar, line gauge, and more |
| `chat_interface.exs` | `mix run examples/chat_interface.exs` | AI chat interface: markdown, textarea, throbber, popup, slash commands |
| `task_manager/` | See [README](https://github.com/mcass19/ex_ratatui/tree/main/examples/task_manager) | Supervised Ecto + SQLite CRUD app. **Also runs over SSH**, multiple clients share one DB |

### Try an example over SSH

```sh
mix run --no-halt examples/system_monitor.exs --ssh
# in another terminal:
ssh demo@localhost -p 2222      # password: demo
```

### Try an example over Erlang Distribution

```sh
# Terminal 1 — start the app node
elixir --sname app --cookie demo -S mix run --no-halt examples/system_monitor.exs --distributed

# Terminal 2 — attach from another node
iex --sname local --cookie demo -S mix
iex> ExRatatui.Distributed.attach(:"app@hostname", SystemMonitor)
```

## Built with ExRatatui

- **[ash_tui](https://github.com/mcass19/ash_tui)** — Interactive terminal explorer for [Ash](https://ash-hq.org) domains, resources, attributes, actions, and more.
- **[switchyard](https://github.com/nshkrdotcom/switchyard)** — Full-featured reducer runtime workbench exercising command batching, async effects, subscription reconciliation, runtime snapshots, distributed attach, and row-scrolled WidgetList.
- **[nerves_ex_ratatui_example](https://github.com/mcass19/nerves_ex_ratatui_example)** — Example [Nerves](https://nerves-project.org) project with three TUIs (system monitor, LED control, and a reducer-runtime system monitor) on embedded hardware, reachable over SSH subsystems and Erlang distribution.
- **[phoenix_ex_ratatui_example](https://github.com/mcass19/phoenix_ex_ratatui_example)** — Example [Phoenix](https://www.phoenixframework.org/) project with two TUIs (callback and reducer runtime) served over SSH and Erlang distribution alongside a public LiveView chat room, sharing PubSub between the browser and the terminal.

## Installation

Add `ex_ratatui` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_ratatui, "~> 0.7"}
  ]
end
```

Then fetch and compile:

```sh
mix deps.get && mix compile
```

A precompiled NIF binary for your platform will be downloaded automatically.
The native library itself is loaded lazily on first use, so compiling a
project that depends on `ex_ratatui` does not require the NIF to be loaded
into the compiler VM.

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

Try the [examples](https://github.com/mcass19/ex_ratatui/tree/main/examples) for more, e.g. `mix run examples/hello_world.exs`.

## Learning Path

New to ExRatatui? Follow this progression:

1. **Run an example** — `mix run examples/hello_world.exs` to see it work
2. **Read [Building UIs](guides/building_uis.md)** — widgets, layout, styles, and events
3. **Read [Callback Runtime](guides/callback_runtime.md)** — build a supervised OTP app with `ExRatatui.App`
4. **Try the counter** — `mix run examples/counter_app.exs` to see callbacks in action
5. **(Optional)** Read [Reducer Runtime](guides/reducer_runtime.md) for async commands and subscriptions
6. **Deploy remotely** — read the [SSH](guides/ssh_transport.md) or [Distribution](guides/distributed_transport.md) guide

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
| [Callback Runtime](guides/callback_runtime.md) | OTP-supervised apps with `mount`, `render`, `handle_event`, and `handle_info` callbacks |
| [Reducer Runtime](guides/reducer_runtime.md) | Elm-style apps with `init`, `update`, `subscriptions`, commands, and runtime inspection |
| [Building UIs](guides/building_uis.md) | Widgets, layout, styles, and events — everything for `render/2` |
| [Custom Widgets](guides/custom_widgets.md) | Compose primitives into reusable widgets via the `ExRatatui.Widget` protocol |
| [Running TUIs over SSH](guides/ssh_transport.md) | Serve any app as a remote TUI over SSH, standalone or under `nerves_ssh` |
| [Running TUIs over Erlang Distribution](guides/distributed_transport.md) | Drive a TUI from a remote BEAM node with zero NIF on the app side |

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

## Testing

ExRatatui includes a headless test backend for CI-friendly rendering verification. Each test terminal is independent, and `test_mode` disables live terminal input polling so `async: true` tests do not race ambient TTY events:

```elixir
test "renders a paragraph" do
  terminal = ExRatatui.init_test_terminal(40, 10)

  paragraph = %Paragraph{text: "Hello!"}
  :ok = ExRatatui.draw(terminal, [{paragraph, %Rect{x: 0, y: 0, width: 40, height: 10}}])

  content = ExRatatui.get_buffer_content(terminal)
  assert content =~ "Hello!"
end
```

For supervised apps started under `test_mode`, use
`ExRatatui.Runtime.inject_event/2` to drive input deterministically:

```elixir
{:ok, pid} = MyApp.TUI.start_link(name: nil, test_mode: {40, 10})

event = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}

:ok = ExRatatui.Runtime.inject_event(pid, event)
```

## Troubleshooting

**Terminal looks garbled or colors are wrong**
Make sure your terminal emulator supports 256-color or true color. Most modern terminals (iTerm2, Ghostty, Alacritty, Windows Terminal, Kitty) work out of the box. If using `tmux` or `screen`, set `TERM=xterm-256color`.

**SSH client hangs or shows no output**
Connect with PTY allocation forced: `ssh -t user@host -p 2222`. Without `-t`, most SSH clients don't allocate a pseudo-terminal, and the TUI has nowhere to render. See the [SSH guide](guides/ssh_transport.md) for details.

**`mix run examples/...` exits immediately**
Make sure you're not piping or redirecting stdin. The TUI needs an interactive terminal to poll events. If running in a non-interactive context, use `--no-halt` for daemon-mode examples (SSH, distributed).

**Tests fail with "terminal_init_failed"**
This happens when a test tries to start a real terminal without a TTY (common in CI or when backgrounding). Use `test_mode: {width, height}` to start a headless test backend instead.

**Debugging rendering issues**
Use the headless test backend to inspect buffer contents:

```elixir
terminal = ExRatatui.init_test_terminal(80, 24)
ExRatatui.draw(terminal, [{widget, rect}])
IO.puts(ExRatatui.get_buffer_content(terminal))
```

For supervised apps, use `ExRatatui.Runtime.snapshot/1` to inspect runtime state and `ExRatatui.Runtime.enable_trace/2` to capture state transitions.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](https://github.com/mcass19/ex_ratatui/blob/main/CONTRIBUTING.md) for development setup and PR guidelines.

## License

MIT — see [LICENSE](https://github.com/mcass19/ex_ratatui/blob/main/LICENSE) for details.
