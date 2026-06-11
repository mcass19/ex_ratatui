# Callback Runtime

The callback runtime is the default way to build supervised TUI applications with `ExRatatui.App`. It follows a LiveView-inspired pattern: mount initial state, render on every state change, and handle events and messages through dedicated callbacks.

This is the mode you want when:

  * You're building a straightforward interactive TUI with direct state management.
  * You want the simplest possible interface — just `mount`, `render`, and `handle_event`.
  * You don't need first-class command or subscription primitives.

For apps that benefit from an Elm-style architecture with commands, subscriptions, and a unified message path, see the [Reducer Runtime](reducer_runtime.md) guide.

## Callback or Reducer?

Both runtimes are transport-agnostic — the same module works over local terminal, SSH, or Erlang distribution without changes. The differences are in how state and side effects flow:

| | Callback Runtime | Reducer Runtime |
|---|---|---|
| Opt-in | `use ExRatatui.App` (default) | `use ExRatatui.App, runtime: :reducer` |
| Entry point | `mount/1` | `init/1` |
| Events | `handle_event/2` + `handle_info/2` | Single `update/2` receives `{:event, _}` and `{:info, _}` |
| Side effects | Direct (send, spawn, etc.) | First-class `Command` primitives (message, send_after, async, batch) |
| Timers | Manual `Process.send_after/3` | Declarative `Subscription` with auto-reconciliation |
| Tracing | Not built-in | Built-in via `ExRatatui.Runtime` |
| Best for | Straightforward interactive TUIs | Apps with async I/O, structured effects, or complex state machines |

## Quick Start

```elixir
defmodule MyApp.TUI do
  use ExRatatui.App

  alias ExRatatui.Event
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  @impl true
  def mount(_opts) do
    {:ok, %{count: 0}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    widget = %Paragraph{
      text: "Count: #{state.count}",
      style: %Style{fg: :white, modifiers: [:bold]},
      alignment: :center,
      block: %Block{
        title: " Counter ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    [{widget, area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, state) do
    {:noreply, %{state | count: state.count + 1}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, state) do
    {:noreply, %{state | count: state.count - 1}}
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

Or run it directly:

```elixir
{:ok, pid} = MyApp.TUI.start_link(name: nil)
```

## Callbacks

| Callback | Required | Description |
|----------|----------|-------------|
| `mount/1` | Yes | Called once on startup. Receives opts from `start_link/1`. Return `{:ok, initial_state}` or `{:error, reason}` |
| `render/2` | Yes | Called after every state change. Receives state and `%Frame{}` with terminal dimensions. Return `[{widget, rect}]` |
| `handle_event/2` | Yes | Called on terminal events (key, mouse, resize). Return `{:noreply, state}` or `{:stop, state}` |
| `handle_info/2` | No | Called for non-terminal messages (e.g., PubSub, `Process.send_after`). Defaults to `{:noreply, state}` |
| `terminate/2` | No | Called on shutdown with reason and final state. Default is a no-op |

### `mount/1`

`mount/1` receives the keyword list passed to `start_link/1`. Use it to set up initial state:

```elixir
def mount(opts) do
  pubsub = Keyword.get(opts, :pubsub)

  if pubsub do
    Phoenix.PubSub.subscribe(pubsub, "updates")
  end

  {:ok, %{messages: [], pubsub: pubsub}}
end
```

When running over SSH or Erlang distribution, `mount/1` also receives `:transport`, `:width`, and `:height` — so your app can adapt its initial state per transport without changing any other callback.

### `render/2`

`render/2` receives the current state and a `%ExRatatui.Frame{}` struct with the terminal's current `width` and `height`. Return a list of `{widget, rect}` tuples — the runtime renders them in order.

See the [Building UIs](../core/building_uis.md) guide for the full widget, layout, and styling reference.

```elixir
def render(state, frame) do
  area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

  [header_area, body_area] =
    Layout.split(area, :vertical, [{:length, 3}, {:min, 0}])

  [
    {%Paragraph{text: "Header"}, header_area},
    {%Paragraph{text: "Body: #{inspect(state)}"}, body_area}
  ]
end
```

### `handle_event/2`

Terminal events arrive as `ExRatatui.Event` structs — see the [Events section](../core/building_uis.md#events) of the Building UIs guide.

```elixir
def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
  {:stop, state}
end

def handle_event(%Event.Key{code: "up", kind: "press"}, state) do
  {:noreply, %{state | selected: max(state.selected - 1, 0)}}
end

def handle_event(_event, state) do
  {:noreply, state}
end
```

### `handle_info/2`

Non-terminal messages (PubSub broadcasts, `Process.send_after` timers, etc.) arrive here:

```elixir
def handle_info({:new_message, msg}, state) do
  {:noreply, %{state | messages: [msg | state.messages]}}
end
```

## Runtime opts

Every transition callback (`mount/1`, `handle_event/2`, `handle_info/2`) can return a third element — a keyword list of runtime opts that adjust the runtime's behaviour for that transition without polluting your domain state:

```elixir
def handle_event(%Event.Key{code: "q"}, state) do
  # Emit an intent for the consumer (e.g. phoenix_ex_ratatui's LV) before exiting.
  {:stop, state, intents: [{:redirect, "/login"}]}
end

def mount(_opts) do
  {:ok, %{n: 0}, trace?: true}
end
```

| Key | Default | Description |
| --- | ------- | ----------- |
| `intents: [...]` | `[]` | Opaque directives forwarded to the transport's `intent_writer_fn` in emission order. ex_ratatui defines no vocabulary — consumers do. Transports without an intent writer (the default `:local` / `:session` / `:distributed_server` / 3-tuple `:cell_session`) silently drop them, so apps stay portable. See [Cell sessions](../transports/cell_session.md) for how a transport wires the writer up. |
| `trace?: bool` | unchanged | Toggle in-memory runtime tracing for debugging — see [Debugging](../internals/debugging.md#runtime-traces). |
| `commands: [...]` | `[]` | Reducer-runtime feature; no-op under the callback runtime. Use `Process.send_after/3` or spawn a `Task` from a callback instead. |
| `render?: bool` | `true` | Reducer-runtime feature; no-op under the callback runtime. |

Intents from a `{:stop, state, intents: ...}` transition fire **before** the server exits, so the example above guarantees the redirect reaches the consumer before the linked-server EXIT propagates. Without that ordering the consumer would see the EXIT first and never get the directive.

## Error Handling and Supervision

ExRatatui apps are supervised GenServers — standard OTP fault tolerance applies:

  * **`mount/1` raises or returns `{:error, reason}`:** The server stops and the supervisor handles the restart according to its strategy (`:one_for_one`, etc.). For SSH and distributed transports, the session is cleaned up and the client sees the connection close.

  * **`render/2` raises:** The error is logged and the frame is skipped — the server continues running with the previous screen content. This prevents a rendering bug from crashing your app.

  * **`handle_event/2` or `handle_info/2` raises:** The server crashes and the supervisor restarts it. Since the GenServer has no way to safely continue with potentially corrupted state, a fresh `mount/1` starts from scratch.

  * **`terminate/2` raises:** The error is ignored — the process exits regardless. Use this callback for best-effort cleanup (e.g., notifying other processes), not for critical operations.

  * **Terminal restoration:** On a local transport crash, the terminal is automatically restored (raw mode disabled, cursor shown) via the Rust ResourceArc finalizer when the terminal reference is garbage collected. You don't need to handle this manually.

  * **SSH client disconnect:** The SSH channel detects the TCP close, the server receives a shutdown signal, and `terminate/2` is called normally.

  * **Distributed client disconnect:** The server monitors the client process. When the client's node goes down, the monitor fires and the server shuts down cleanly.

For production deployments, set appropriate `:max_restarts` and `:max_seconds` on your supervisor to prevent restart loops.

## Running Over Transports

The same app module works across all three transports with zero code changes:

```elixir
children = [
  {MyApp.TUI, []},                                    # local TTY
  {MyApp.TUI, transport: :ssh, port: 2222, ...},      # remote over SSH
  {MyApp.TUI, transport: :distributed}                 # remote over distribution
]
```

See the [Running TUIs over SSH](../transports/ssh_transport.md) and [Running TUIs over Erlang Distribution](../transports/distributed_transport.md) guides for transport-specific setup, options, and authentication.

### Local terminal opts

The `:local` transport (default when no `:transport` is given) accepts two extra opts on `start_link`:

  * `:mouse_capture` — enable mouse reporting (clicks, scroll, drag, move) as `%Event.Mouse{}` from `poll_event/1`. Off by default because mouse-capture mode disables the terminal's native text-selection while the app is running. Pair with `ExRatatui.Focus.handle_mouse/2` to route clicks.
  * `:focus_events` — enable terminal-window focus reporting (`%Event.FocusGained{}` / `%Event.FocusLost{}`). Off by default because the request leaves `CSI ?1004h` on the user's tty; any window-switch then queues focus bytes that can leak into unrelated stdin consumers (a plain shell or `mix test` started later).

```elixir
children = [
  {MyApp.TUI, mouse_capture: true, focus_events: true}
]
```

SSH and Distributed transports decode mouse events unconditionally because their VTE-based input parser handles them regardless; the opts above only matter for `:local`.

## Testing

Start the app under `test_mode` with explicit dimensions and use `ExRatatui.Runtime.inject_event/2` for deterministic input:

```elixir
test "increments on up key" do
  {:ok, pid} = MyApp.TUI.start_link(name: nil, test_mode: {40, 10})

  event = %ExRatatui.Event.Key{code: "up", modifiers: [], kind: "press"}
  :ok = ExRatatui.Runtime.inject_event(pid, event)

  snapshot = ExRatatui.Runtime.snapshot(pid)
  assert snapshot.render_count >= 2

  GenServer.stop(pid)
end
```

`test_mode` disables live terminal input polling so `async: true` tests don't race ambient TTY events.

## Examples

  * [`examples/basics/counter_app.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/counter_app.exs) — simple counter with key events
  * [`examples/apps/system_monitor.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/system_monitor.exs) — Linux system dashboard with CPU, memory, disk, network, and BEAM stats (also runs over SSH and Erlang distribution)
  * [`examples/apps/task_manager_db/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/apps/task_manager_db) — supervised Ecto + SQLite CRUD app with tabs, table, scrollbar, and SSH support
  * [`phoenix_ex_ratatui_example`](https://github.com/mcass19/phoenix_ex_ratatui_example) — Phoenix app with an admin TUI over SSH and Erlang distribution, sharing PubSub with LiveView (also includes a [reducer-runtime TUI](https://github.com/mcass19/phoenix_ex_ratatui_example/blob/main/lib/phoenix_ex_ratatui_example/stats_reducer_tui.ex))
  * [`nerves_ex_ratatui_example`](https://github.com/mcass19/nerves_ex_ratatui_example) — Nerves firmware with system monitor and LED control TUIs over SSH subsystems and Erlang distribution (also includes a [reducer-runtime system monitor](https://github.com/mcass19/nerves_ex_ratatui_example/blob/main/lib/system_monitor_reducer_tui.ex))

## Related

  * `ExRatatui.App` — behaviour module
  * [Reducer Runtime](reducer_runtime.md) — alternative runtime with commands and subscriptions
  * [Building UIs](../core/building_uis.md) — widgets, layout, styles, and events
  * [Running TUIs over SSH](../transports/ssh_transport.md) — SSH transport
  * [Running TUIs over Erlang Distribution](../transports/distributed_transport.md) — distribution transport
