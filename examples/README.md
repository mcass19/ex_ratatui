# Examples

A catalog of runnable ExRatatui examples. Each stands alone — start with `hello_world` or `counter_app`, then browse the rest for patterns you want to copy.

Most examples run under a real terminal. One — `cell_dump.exs` — is **headless**: it drives `ExRatatui.CellSession` (a `TestBackend`-backed sibling of `ExRatatui.Session`) and prints to stdout, so it never touches your tty and exits cleanly.

Some terminal examples also work over SSH (`--ssh`) or Erlang distribution (`--distributed`); the flag is noted where it applies.

## Catalog

| Example | Run | What to see |
|---------|-----|-------------|
| [`hello_world.exs`](hello_world.exs) | `mix run examples/hello_world.exs` | Minimal `ExRatatui.run/1` loop — a styled paragraph, one keypress to exit. The smallest working TUI. |
| [`counter.exs`](counter.exs) | `mix run examples/counter.exs` | Same loop plus key events. Up/Down keys mutate a counter; shows the render/poll cycle without `ExRatatui.App`. |
| [`counter_app.exs`](counter_app.exs) | `mix run examples/counter_app.exs` | The same counter, this time as a supervised `ExRatatui.App` with `mount/1`, `render/2`, `handle_event/2`. The typical starting point for real apps. |
| [`reducer_counter_app.exs`](reducer_counter_app.exs) | `mix run examples/reducer_counter_app.exs` | Counter on the reducer runtime. Demonstrates `init/1` + `update/2`, a 1-second `Subscription.interval`, and `render?: false` for tick bookkeeping. |
| [`widget_showcase.exs`](widget_showcase.exs) | `mix run examples/widget_showcase.exs` | Tabbed showcase of progress bars, checkboxes, text input, scrollable logs, and more. Good reference for what each widget looks like. |
| [`rich_text_showcase.exs`](rich_text_showcase.exs) | `mix run examples/rich_text_showcase.exs` | Demonstrates `Span`/`Line` across `Paragraph`, `List`, `Table`, `Tabs`, and `Block` titles — per-span colors and modifiers. |
| [`focus_multi_panel.exs`](focus_multi_panel.exs) | `mix run examples/focus_multi_panel.exs` | Three-panel layout with Tab-cycled focus using `ExRatatui.Focus`. Shows the keymap pattern for dispatching keys to the active panel. |
| [`text_input_cjk.exs`](text_input_cjk.exs) | `mix run examples/text_input_cjk.exs` | `TextInput` handling CJK / wide characters — cursor math with multi-column glyphs. |
| [`custom_widgets.exs`](custom_widgets.exs) | `mix run examples/custom_widgets.exs` | Pure-Elixir composite widgets via the `ExRatatui.Widget` protocol: status badge + key/value pair, no Rust. |
| [`chat_interface.exs`](chat_interface.exs) | `mix run examples/chat_interface.exs` | AI chat UI: `Markdown`, `Textarea`, `Throbber`, `Popup`, `SlashCommands`. The most visually rich example. |
| [`task_manager.exs`](task_manager.exs) | `mix run examples/task_manager.exs` | Full task manager — tabs, table, scrollbar, line gauge. In-memory state; a good end-to-end reducer example. |
| [`task_manager/`](task_manager/) | See the [subdir README](task_manager/README.md) | Supervised Ecto + SQLite CRUD app. Also runs over SSH where multiple clients share one DB. |
| [`system_monitor.exs`](system_monitor.exs) | `mix run examples/system_monitor.exs` | Linux system dashboard: CPU, memory, disk, network, BEAM stats. Linux/Nerves only. Also supports `--ssh` and `--distributed` (see below). |
| [`cell_dump.exs`](cell_dump.exs) | `mix run examples/cell_dump.exs` | **Headless.** Renders a styled paragraph in a bordered block into a `CellSession`, then prints the buffer to stdout. Visual sanity check for the cell-extraction pipeline; starting point for non-terminal renderers (browser, framebuffer, SVG). |
| [`image_demo.exs`](image_demo.exs) | `mix run examples/image_demo.exs` | Interactive image renderer. Loads a photo (picsum.photos or `IMAGE_PATH`) and lets you toggle protocol (auto/halfblocks/kitty/sixel/iterm2) and resize mode (fit/crop/scale) at runtime. Status panel shows live render output dimensions. Also supports `--ssh` and `--distributed` for smoke-testing those transports end-to-end. |
| [`headless_image.exs`](headless_image.exs) | `mix run examples/headless_image.exs` | **Headless.** Fetches an image and renders it through `CellSession` into halfblocks (with ANSI colors), dumping the cell grid to stdout. Proves the same model code that uses Kitty graphics in a real terminal works under Livebook / Kino / snapshot tests. |

The [Getting Started](../guides/getting_started.md) guide builds a todo app from scratch using the same patterns.

## Try an example over SSH

```sh
mix run --no-halt examples/system_monitor.exs --ssh
# in another terminal:
ssh demo@localhost -p 2222      # password: demo
```

Any `ExRatatui.App` can be served over SSH — the example just wires up `transport: :ssh` with a demo password. See [Running TUIs over SSH](../guides/ssh_transport.md) for the full story.

## Try an example over Erlang Distribution

```sh
# Terminal 1 — start the app node
elixir --sname app --cookie demo -S mix run --no-halt examples/system_monitor.exs --distributed

# Terminal 2 — attach from another node
iex --sname local --cookie demo -S mix
iex> ExRatatui.Distributed.attach(:"app@hostname", SystemMonitor)
```

The app node runs the BEAM logic; the client node owns the terminal (and the NIF). Ideal for Nerves-on-a-box workflows where the device has no human console. See [Running TUIs over Erlang Distribution](../guides/distributed_transport.md).

