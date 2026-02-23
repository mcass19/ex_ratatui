# ExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/ex_ratatui.svg)](https://hex.pm/packages/ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/ex_ratatui)
[![CI](https://github.com/mcass19/ex_ratatui/actions/workflows/ci.yml/badge.svg)](https://github.com/mcass19/ex_ratatui/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/ex_ratatui.svg)](https://github.com/mcass19/ex_ratatui/blob/main/LICENSE)

Elixir bindings for the Rust [ratatui](https://ratatui.rs) terminal UI library, via [Rustler](https://github.com/rustler-beam/rustler) NIFs.

Build rich terminal UIs in Elixir with ratatui's layout engine, widget library, and styling system — without blocking the BEAM.

![ExRatatui Demo](assets/demo.gif)

## Features

- 5 built-in widgets (for now!): Paragraph, Block, List, Table, Gauge
- Constraint-based layout engine (percentage, length, min, max, ratio)
- Non-blocking keyboard, mouse, and resize event polling
- **OTP-supervised TUI apps** via `ExRatatui.App` behaviour with LiveView-inspired callbacks
- Full color support: named, RGB, and 256-color indexed
- Text modifiers: bold, italic, underlined, and more
- Headless test backend for CI-friendly rendering verification
- Precompiled NIF binaries — no Rust toolchain needed
- Runs on BEAM's DirtyIo scheduler — never blocks your processes

## Examples

| Example | Run | Description |
|---------|-----|-------------|
| `hello_world.exs` | `mix run examples/hello_world.exs` | Minimal paragraph display |
| `counter.exs` | `mix run examples/counter.exs` | Interactive counter with key events |
| `counter_app.exs` | `mix run examples/counter_app.exs` | Counter using `ExRatatui.App` behaviour |
| `system_monitor.exs` | `mix run examples/system_monitor.exs` | System dashboard (CPU, memory, disk, network, BEAM stats) |
| `task_manager.exs` | `mix run examples/task_manager.exs` | Full task manager with all widgets |
| `task_manager/` | See [README](https://github.com/mcass19/ex_ratatui/tree/main/examples/task_manager) | Supervised Ecto + SQLite CRUD app |

## Installation

Add `ex_ratatui` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_ratatui, "~> 0.3"}
  ]
end
```

Then fetch and compile:

```sh
mix deps.get && mix compile
```

A precompiled NIF binary for your platform will be downloaded automatically.

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

Run it with `mix run examples/hello_world.exs`.

## OTP App Behaviour

For supervised TUI applications, use the `ExRatatui.App` behaviour — a LiveView-inspired callback interface that manages the terminal lifecycle under OTP:

```elixir
defmodule MyApp.TUI do
  use ExRatatui.App

  @impl true
  def mount(_opts) do
    {:ok, %{count: 0}}
  end

  @impl true
  def render(state, frame) do
    alias ExRatatui.Widgets.Paragraph
    alias ExRatatui.Layout.Rect

    widget = %Paragraph{text: "Count: #{state.count}"}
    rect = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [{widget, rect}]
  end

  @impl true
  def handle_event(%ExRatatui.Event.Key{code: "q"}, state) do
    {:stop, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: "up"}, state) do
    {:noreply, %{state | count: state.count + 1}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
```

Add it to your supervision tree:

```elixir
children = [{MyApp.TUI, []}]
Supervisor.start_link(children, strategy: :one_for_one)
```

### Callbacks

| Callback | Description |
|----------|-------------|
| `mount/1` | Called once on startup. Return `{:ok, initial_state}` |
| `render/2` | Called after every state change. Receives state and `%Frame{}` with terminal dimensions. Return `[{widget, rect}]` |
| `handle_event/2` | Called on terminal events. Return `{:noreply, state}` or `{:stop, state}` |
| `handle_info/2` | Called for non-terminal messages (e.g., PubSub). Optional — defaults to `{:noreply, state}` |
| `terminate/2` | Called on shutdown with reason and final state. Optional — default is a no-op |

See the [task_manager example](https://github.com/mcass19/ex_ratatui/tree/main/examples/task_manager) for a full Ecto-backed app using this behaviour.

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

## Widgets

### Paragraph

Text display with alignment, wrapping, and scrolling.

```elixir
%Paragraph{
  text: "Hello, world!\nSecond line.",
  style: %Style{fg: :cyan, modifiers: [:bold]},
  alignment: :center,
  wrap: true
}
```

### Block

Container with borders and title. Can wrap any other widget via the `:block` field.

```elixir
%Block{
  title: "My Panel",
  borders: [:all],
  border_type: :rounded,
  border_style: %Style{fg: :blue}
}

# Compose with other widgets:
%Paragraph{
  text: "Inside a box",
  block: %Block{title: "Title", borders: [:all]}
}
```

### List

Selectable list with highlight support.

```elixir
%List{
  items: ["Elixir", "Rust", "Haskell"],
  highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
  highlight_symbol: " > ",
  selected: 0,
  block: %Block{title: " Languages ", borders: [:all]}
}
```

### Table

Table with headers, rows, and column width constraints.

```elixir
%Table{
  rows: [["Alice", "30"], ["Bob", "25"]],
  header: ["Name", "Age"],
  widths: [{:length, 15}, {:length, 10}],
  highlight_style: %Style{fg: :yellow},
  selected: 0
}
```

### Gauge

Progress bar.

```elixir
%Gauge{
  ratio: 0.75,
  label: "75%",
  gauge_style: %Style{fg: :green}
}
```

## Layout

Split areas into sub-regions using constraints:

```elixir
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect

area = %Rect{x: 0, y: 0, width: 80, height: 24}

# Three-row layout: header, body, footer
[header, body, footer] = Layout.split(area, :vertical, [
  {:length, 3},
  {:min, 0},
  {:length, 1}
])

# Split body into sidebar + main
[sidebar, main] = Layout.split(body, :horizontal, [
  {:percentage, 30},
  {:percentage, 70}
])
```

Constraint types: `{:percentage, n}`, `{:length, n}`, `{:min, n}`, `{:max, n}`, `{:ratio, num, den}`.

## Events

Poll for keyboard, mouse, and resize events without blocking the BEAM:

```elixir
case ExRatatui.poll_event(100) do
  %Event.Key{code: "q", kind: "press"} ->
    :quit

  %Event.Key{code: "up", kind: "press"} ->
    :move_up

  %Event.Key{code: "j", kind: "press", modifiers: ["ctrl"]} ->
    :ctrl_j

  %Event.Resize{width: w, height: h} ->
    {:resized, w, h}

  nil ->
    :timeout
end
```

## Styles

```elixir
# Named colors
%Style{fg: :green, bg: :black}

# RGB
%Style{fg: {:rgb, 255, 100, 0}}

# 256-color indexed
%Style{fg: {:indexed, 42}}

# Modifiers
%Style{modifiers: [:bold, :italic, :underlined]}
```

## Testing

ExRatatui includes a headless test backend for CI-friendly rendering verification. Each test terminal is independent, enabling `async: true` tests:

```elixir
test "renders a paragraph" do
  terminal = ExRatatui.init_test_terminal(40, 10)

  paragraph = %Paragraph{text: "Hello!"}
  :ok = ExRatatui.draw(terminal, [{paragraph, %Rect{x: 0, y: 0, width: 40, height: 10}}])

  content = ExRatatui.get_buffer_content(terminal)
  assert content =~ "Hello!"
end
```

## Development

```sh
git clone https://github.com/mcass19/ex_ratatui.git
cd ex_ratatui
mix deps.get
mix test
```

To compile the NIF from source, install the [Rust toolchain](https://rustup.rs/) and set `EX_RATATUI_BUILD=true`.

## License

MIT — see [LICENSE](https://github.com/mcass19/ex_ratatui/blob/main/LICENSE) for details.
