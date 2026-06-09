# Examples

A catalog of runnable ExRatatui examples, grouped by folder. Each example stands alone, copy any one as a starting point.

Most examples run under a real terminal. The two under `cell_session/` are **headless**: they drive `ExRatatui.CellSession` and print to stdout, so they never touch a tty and exit cleanly.

Some terminal examples also work over SSH (`--ssh`) or Erlang distribution (`--distributed`); the flag is noted where it applies (see the bottom of this file).

## Start here

A four-step on-ramp, simplest first:

1. [`basics/hello_world.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/hello_world.exs) — the smallest working TUI.
2. [`basics/counter_app.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/counter_app.exs) — the typical starting point for a real app (`ExRatatui.App`).
3. [`basics/reducer_counter_app.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/reducer_counter_app.exs) — the same counter on the reducer runtime.
4. [`apps/chat.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/chat.exs) — a full flagship app once the basics click.

The [Getting Started](../guides/getting_started.md) guide builds a todo app from scratch using the same patterns.

## Basics

The runtime loop, four ways — from a raw render/poll loop to the supervised runtimes.

| Example | Run | What to see |
|---------|-----|-------------|
| [`hello_world.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/hello_world.exs) | `mix run examples/basics/hello_world.exs` | Minimal `ExRatatui.run/1` loop — a styled paragraph, one keypress to exit. The smallest working TUI. |
| [`counter.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/counter.exs) | `mix run examples/basics/counter.exs` | Same loop plus key events. Up/Down keys mutate a counter; shows the render/poll cycle without `ExRatatui.App`. |
| [`counter_app.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/counter_app.exs) | `mix run examples/basics/counter_app.exs` | The same counter, this time as a supervised `ExRatatui.App` with `mount/1`, `render/2`, `handle_event/2`. The typical starting point for real apps. |
| [`reducer_counter_app.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/reducer_counter_app.exs) | `mix run examples/basics/reducer_counter_app.exs` | Counter on the reducer runtime. Demonstrates `init/1` + `update/2`, a 1-second `Subscription.interval`, and `render?: false` for tick bookkeeping. |

## Widgets

Focused, copyable demos — each centered on one widget or text feature.

| Example | Run | What to see |
|---------|-----|-------------|
| [`table.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/table.exs) | `mix run examples/widgets/table.exs` | Spreadsheet-style table exercising every Table field: `:footer`, `:header_style`, `:footer_style`, `:column_highlight_style`, `:cell_highlight_style`, `:selected_column`, and `:highlight_spacing: :always`. Arrow keys move the selected row + column; the intersection cell pops with a bright tint. |
| [`rich_text.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/rich_text.exs) | `mix run examples/widgets/rich_text.exs` | `Span`/`Line` across `Paragraph`, `List`, `Table`, `Tabs`, and `Block` titles — per-span colors and modifiers. |
| [`text_input_cjk.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/text_input_cjk.exs) | `mix run examples/widgets/text_input_cjk.exs` | `TextInput` handling CJK / wide characters — cursor math with multi-column glyphs. |
| [`big_text.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/big_text.exs) | `mix run examples/widgets/big_text.exs` | Interactive `BigText` viewer for slide-deck titles. Cycle through all eight `pixel_size` variants, three alignments, six colors, and four sample headlines at runtime. |
| [`code_block.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/code_block.exs) | `mix run examples/widgets/code_block.exs` | Interactive `CodeBlock` viewer. Cycle through all seven syntect themes and five sample languages, toggle the line-number gutter, and toggle line-range emphasis. |
| [`custom_widget.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/custom_widget.exs) | `mix run examples/widgets/custom_widget.exs` | Pure-Elixir composite widgets via the `ExRatatui.Widget` protocol: status badge + key/value pair, no Rust. |
| [`barchart.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/barchart.exs) | `mix run examples/widgets/barchart.exs` | `BarChart` in three forms — vertical, horizontal, and grouped (`Bar`/`BarGroup`). Left/Right highlights a weekday bar. |
| [`sparkline.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/sparkline.exs) | `mix run examples/widgets/sparkline.exs` | `Sparkline` over a rolling series, including `nil` (absent) samples rendered with `absent_value_symbol`. Space shifts in a new sample. |
| [`chart.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/chart.exs) | `mix run examples/widgets/chart.exs` | `Chart` with two line `Dataset`s and x/y `Axis`. Cycle legend position (`l`) and marker (`m`) at runtime. |
| [`calendar.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/calendar.exs) | `mix run examples/widgets/calendar.exs` | `Calendar` month view with styled events and a movable cursor. Arrow keys move by day/week; Space toggles an event. |
| [`canvas.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/canvas.exs) | `mix run examples/widgets/canvas.exs` | `Canvas` shapes (`Line`, `Circle`, `Rectangle`, `Points`) in a bounded space, plus a world map via `Canvas.Map` + `Label`. Arrow keys move a cursor point. |
| [`checkbox.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/checkbox.exs) | `mix run examples/widgets/checkbox.exs` | `Checkbox` settings list with a moving cursor. Up/Down moves; Space toggles. |
| [`markdown.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/markdown.exs) | `mix run examples/widgets/markdown.exs` | `Markdown` rendering bold/italic/lists/tables and a syntax-highlighted code block. Up/Down scrolls. |
| [`throbber.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/throbber.exs) | `mix run examples/widgets/throbber.exs` | `Throbber` spinners, one per `throbber_set`, animated on the **reducer runtime** via a `Subscription.interval` tick. |
| [`popup.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/popup.exs) | `mix run examples/widgets/popup.exs` | `Popup` overlaying a centered widget on the background, sized as a percentage of the area. Space toggles it. |
| [`widget_list.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/widget_list.exs) | `mix run examples/widgets/widget_list.exs` | `WidgetList` composing heterogeneous, multi-line items (labels, paragraphs, markdown) in one scrollable column. Up/Down scrolls. |
| [`slash_commands.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/slash_commands.exs) | `mix run examples/widgets/slash_commands.exs` | `SlashCommands` autocomplete: type `/` to match commands, Up/Down to select, Enter/Tab to complete. |
| [`gauge.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/gauge.exs) | `mix run examples/widgets/gauge.exs` | `Gauge` block progress bars with percentage labels. Up/Down adjusts the top gauge. |
| [`line_gauge.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/line_gauge.exs) | `mix run examples/widgets/line_gauge.exs` | `LineGauge` single-line bars (`filled_style`/`unfilled_style`) stacked as a metrics panel. Up/Down adjusts CPU. |
| [`scrollbar.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/scrollbar.exs) | `mix run examples/widgets/scrollbar.exs` | `Scrollbar` bound to a scrollable `List` — its thumb tracks the selected position. Up/Down moves. |
| [`tabs.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/tabs.exs) | `mix run examples/widgets/tabs.exs` | `Tabs` bar selecting between content panes. Left/Right or Tab switches the active tab. |
| [`list.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/list.exs) | `mix run examples/widgets/list.exs` | `List` with a selection highlight and `highlight_symbol`. Up/Down moves; g/G jumps to top/bottom. |
| [`textarea.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/textarea.exs) | `mix run examples/widgets/textarea.exs` | `Textarea` multi-line editor with a live line/cursor status. Type to edit; Enter inserts a newline. |
| [`clear.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/clear.exs) | `mix run examples/widgets/clear.exs` | `Clear` blanks a region before a hand-rolled overlay. Space toggles it to show the background bleeding through. |

## Layout & styling

Constraint-based layout, multi-panel focus, and theming.

| Example | Run | What to see |
|---------|-----|-------------|
| [`flex.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/layout/flex.exs) | `mix run examples/layout/flex.exs` | Visual reference card for `Layout.split/4` opts: one row per `:flex` mode (`:start`, `:center`, `:end`, `:space_between`, `:space_around`) with `spacing:` gutters, plus `{:fill, n}` weighted panels. |
| [`focus.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/layout/focus.exs) | `mix run examples/layout/focus.exs` | Three-panel layout with Tab-cycled focus via `ExRatatui.Focus`: keyboard focus (Tab/Shift+Tab), mouse click-to-focus, scroll-wheel routing, bracketed paste, terminal-window focus reporting, `ExRatatui.Theme` threading, and `%Block.Title{}` status badges. Opts into `mouse_capture: true`. |
| [`theme.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/layout/theme.exs) | `mix run examples/layout/theme.exs` | Visual reference for `ExRatatui.Theme`. Left: one swatch per semantic slot. Right: a live preview of `border_style/2`, `text_style/2`, and `selection_style/1`. Press `1`/`2`/`3` to switch between `default/0`, `light/0`, and a custom Nord-ish theme. |

## Apps

Flagship, end-to-end applications — the sophisticated anchors.

| Example | Run | What to see |
|---------|-----|-------------|
| [`chat.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/chat.exs) | `mix run examples/apps/chat.exs` | AI chat UI: `Markdown`, `Textarea`, `Throbber`, `Popup`, `WidgetList`, `SlashCommands`. The most visually rich example. |
| [`chat_log.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/chat_log.exs) | `mix run examples/apps/chat_log.exs` | Chat UI with `List{direction: :bottom_to_top}` history pinned to the bottom, a multi-line `Textarea` composer with bracketed paste, a multi-title `Block` header, `Layout.Padding`, `set_terminal_title/1`, and `ExRatatui.Theme`. Tab cycles focus; Alt+Enter inserts a newline. |
| [`task_manager.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/task_manager.exs) | `mix run examples/apps/task_manager.exs` | Full task manager — tabs, table, scrollbar, line gauge. In-memory state; a good end-to-end reducer example. |
| [`task_manager_db/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/apps/task_manager_db) | See the [subdir README](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/task_manager_db/README.md) | Supervised Ecto + SQLite CRUD app. Also runs over SSH where multiple clients share one DB. |
| [`system_monitor.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/system_monitor.exs) | `mix run examples/apps/system_monitor.exs` | Linux system dashboard: CPU, memory, disk, network, BEAM stats. Linux/Nerves only. Also supports `--ssh` and `--distributed` (see below). |

## Cell session

Non-terminal rendering — drive `ExRatatui.CellSession` and consume the cell buffer.

| Example | Run | What to see |
|---------|-----|-------------|
| [`cell_dump.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/cell_session/cell_dump.exs) | `mix run examples/cell_session/cell_dump.exs` | **Headless.** Renders a styled paragraph in a bordered block into a `CellSession`, then prints the buffer to stdout. Visual sanity check for the cell-extraction pipeline; starting point for non-terminal renderers (browser, framebuffer, SVG). |
| [`headless_image.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/cell_session/headless_image.exs) | `mix run examples/cell_session/headless_image.exs` | **Headless.** Fetches an image and renders it through `CellSession` into halfblocks (with ANSI colors), dumping the cell grid to stdout. Proves the same model code that uses Kitty graphics in a real terminal works under Livebook / Kino / snapshot tests. |

## Images

| Example | Run | What to see |
|---------|-----|-------------|
| [`image_demo.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/images/image_demo.exs) | `mix run examples/images/image_demo.exs` | Interactive image renderer. Loads a photo (picsum.photos or `IMAGE_PATH`) and toggles protocol (auto/halfblocks/kitty/sixel/iterm2) and resize mode (fit/crop/scale) at runtime. Status panel shows live render output dimensions. Also supports `--ssh` and `--distributed`. |

## Observability & patterns

Runnable companions to the Telemetry and State Machine guides.

| Example | Run | What to see |
|---------|-----|-------------|
| [`telemetry.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/observability/telemetry.exs) | `mix run examples/observability/telemetry.exs` | A TUI that attaches a `:telemetry` handler to its own runtime/render `:stop` events and renders the live counts. Pairs with [Telemetry](../guides/telemetry.md). |
| [`state_machine.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/observability/state_machine.exs) | `mix run examples/observability/state_machine.exs` | Screen-as-data dispatch (`:main`/`:settings`) with a modal `:overlay` that intercepts input — a confirm-quit `Popup`. Pairs with [State Machine Patterns](../guides/state_machines.md). |

## Try an example over SSH

```sh
mix run --no-halt examples/apps/system_monitor.exs --ssh
# in another terminal:
ssh demo@localhost -p 2222      # password: demo
```

Any `ExRatatui.App` can be served over SSH — the example just wires up `transport: :ssh` with a demo password. See [Running TUIs over SSH](../guides/ssh_transport.md) for the full story.

## Try an example over Erlang Distribution

```sh
# Terminal 1 — start the app node
elixir --sname app --cookie demo -S mix run --no-halt examples/apps/system_monitor.exs --distributed

# Terminal 2 — attach from another node
iex --sname local --cookie demo -S mix
iex> ExRatatui.Distributed.attach(:"app@hostname", SystemMonitor)
```

The app node runs the BEAM logic; the client node owns the terminal (and the NIF). See [Running TUIs over Erlang Distribution](../guides/distributed_transport.md).
