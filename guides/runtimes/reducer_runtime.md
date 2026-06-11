# Reducer Runtime

The reducer runtime is an alternative way to build supervised TUI applications with `ExRatatui.App`. Inspired by The Elm Architecture, it routes all messages through a single `update/2` function and provides first-class primitives for side effects (`ExRatatui.Command`) and recurring timers (`ExRatatui.Subscription`).

Reach for this mode when:

  * The TUI has async operations (HTTP calls, file I/O) that call for structured side-effect handling.
  * Recurring timers that reconcile automatically when state changes are needed.
  * A single message path is preferable to separate `handle_event` and `handle_info` callbacks.
  * Built-in runtime inspection and tracing for debugging are wanted.

For simpler apps that don't need commands or subscriptions, see the [Callback Runtime](callback_runtime.md) guide — its [side-by-side comparison table](callback_runtime.md#callback-or-reducer) summarizes the differences.

## Quick start

```elixir
defmodule MyApp.TUI do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Command, Event, Subscription}
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  @impl true
  def init(_opts) do
    {:ok, %{count: 0}, commands: [Command.message(:boot)]}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [{%Paragraph{text: "Count: #{state.count}"}, area}]
  end

  @impl true
  def update({:event, %Event.Key{code: "q", kind: "press"}}, state) do
    {:stop, state}
  end

  def update({:event, %Event.Key{code: "up", kind: "press"}}, state) do
    {:noreply, %{state | count: state.count + 1}}
  end

  def update({:info, :boot}, state) do
    {:noreply, %{state | count: 1}}
  end

  def update({:info, :tick}, state) do
    {:noreply, %{state | count: state.count + 1}}
  end

  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state) do
    [Subscription.interval(:heartbeat, 1_000, :tick)]
  end
end
```

Add it to the supervision tree or run directly:

```elixir
children = [{MyApp.TUI, []}]
Supervisor.start_link(children, strategy: :one_for_one)
```

## Callbacks

| Callback | Required | Description |
|----------|----------|-------------|
| `init/1` | Yes | Called once on startup. Return `{:ok, state}` or `{:ok, state, opts}` |
| `render/2` | Yes | Called after every state change. Return `[{widget, rect}]` |
| `update/2` | Yes | Receives `{:event, event}` or `{:info, message}`. Return `{:noreply, state}`, `{:noreply, state, opts}`, or `{:stop, state}`. End with a catch-all clause — unmatched messages crash the server |
| `subscriptions/1` | No | Called after each state transition. Return a list of `Subscription` structs. Defaults to `[]` |
| `terminate/2` | No | Called on shutdown. Default is a no-op |

### The message path

Unlike the callback runtime which splits terminal events (`handle_event/2`) from mailbox messages (`handle_info/2`), the reducer runtime routes everything through `update/2`:

  * **Terminal input** arrives as `{:event, event}` — key presses, mouse clicks, resize events.
  * **Mailbox messages** arrive as `{:info, message}` — PubSub broadcasts, timer messages, async command results.

```elixir
def update({:event, %Event.Key{code: "q"}}, state), do: {:stop, state}
def update({:event, %Event.Mouse{kind: "down"}}, state), do: {:noreply, state}
def update({:info, :tick}, state), do: {:noreply, state}
def update({:info, {:data_loaded, data}}, state), do: {:noreply, %{state | data: data}}
def update(_msg, state), do: {:noreply, state}
```

### Runtime options

Both `init/1` and `update/2` can return runtime options as a third element:

```elixir
def init(_opts) do
  {:ok, %{count: 0}, commands: [Command.message(:boot)], trace?: true}
end

def update({:info, :background_work}, state) do
  {:noreply, state, render?: false, commands: [Command.async(fn -> do_work() end, &handle_result/1)]}
end

def update({:event, %Event.Key{code: "q"}}, state) do
  # Tell the transport's consumer we want to navigate away. Opaque to
  # ex_ratatui — the consumer (e.g. phoenix_ex_ratatui) decides what
  # `{:redirect, _}` means.
  {:stop, state, intents: [{:redirect, "/login"}]}
end
```

| Option | Default | Description |
|--------|---------|-------------|
| `commands: [...]` | `[]` | Side effects to execute after the state transition |
| `intents: [...]` | `[]` | Opaque directives forwarded to the transport's `intent_writer_fn` in emission order. See [Intents](#intents) below. |
| `render?: bool` | `true` | Whether to re-render after this transition |
| `trace?: bool` | unchanged | Enable or disable in-memory runtime tracing |

`ExRatatui.App`'s Runtime opts section has the full list (including `probe_image_protocol:`).

### Intents

An intent is an arbitrary term — ex_ratatui never inspects it. The runtime forwards each intent the callbacks emit to the transport's `intent_writer_fn` in the order they were emitted. The vocabulary is consumer-defined: `phoenix_ex_ratatui` recognises `{:navigate, path}`, `{:patch, path}`, `{:redirect, path}`, and `{:redirect, [external: url]}`, dispatching them to the equivalent `Phoenix.LiveView` action.

Transports that don't supply an `intent_writer_fn` (the default `:local` / `:session` / `:distributed_server` / 3-tuple `:cell_session`) silently drop intents. That's deliberate — the same App can run unchanged over an SSH tty (no consumer to navigate, drop) and a LiveView (consumer dispatches the intent). See [Cell sessions](../transports/cell_session.md) for how a transport author wires the writer up.

Intents from a `{:stop, state, intents: ...}` transition fire **before** the server exits, so the example above guarantees the `:redirect` reaches the consumer before the linked-server EXIT propagates.

## Commands

Commands are one-shot side effects scheduled from `init/1` or `update/2`. They execute after the new state has been committed and rendered.

### `Command.message/1`

Send an immediate self-message:

```elixir
Command.message(:refresh)
# The app receives {:info, :refresh} in update/2
```

### `Command.send_after/2`

Schedule a delayed self-message:

```elixir
Command.send_after(5_000, :timeout)
# After 5 seconds, the app receives {:info, :timeout}
```

### `Command.async/2`

Run a function in the background and map the result back into an app message:

```elixir
Command.async(
  fn -> HTTPClient.get!("/api/data") end,
  fn result -> {:data_loaded, result} end
)
```

The mapper receives the function's return value on success. If the function raises, exits, or throws, the mapper receives `{:error, reason}` instead. If the mapper itself fails, the runtime wraps that into an error tuple too — the async command always completes cleanly.

```elixir
def update({:info, {:data_loaded, {:error, reason}}}, state) do
  {:noreply, %{state | error: reason}}
end

def update({:info, {:data_loaded, body}}, state) do
  {:noreply, %{state | data: body}}
end
```

### `Command.batch/1`

Group multiple commands into a single return value:

```elixir
Command.batch([
  Command.message(:refresh_ui),
  Command.async(fn -> fetch_data() end, &handle_data/1)
])
```

### `Command.none/0`

Explicit no-op — useful when building commands conditionally:

```elixir
commands = if state.auto_refresh, do: [Command.send_after(1_000, :refresh)], else: [Command.none()]
{:noreply, state, commands: commands}
```

## Subscriptions

Subscriptions are recurring or one-shot timers declared in `subscriptions/1`. The runtime reconciles them after each state transition — diffing by stable ID so there's no need to manage timer references manually.

### `Subscription.interval/3`

Repeated self-message at a fixed interval:

```elixir
def subscriptions(state) do
  if state.polling? do
    [Subscription.interval(:poll, 1_000, :poll_data)]
  else
    []
  end
end
```

When `state.polling?` flips to `false`, the runtime automatically cancels the timer. When it flips back to `true`, a new timer starts. If the interval or message changes for the same ID, the old timer is cancelled and a new one is armed.

### `Subscription.once/3`

One-shot self-message delivered once after a delay:

```elixir
def subscriptions(_state) do
  [Subscription.once(:startup_delay, 2_000, :delayed_init)]
end
```

After firing, a `:once` subscription does not rearm — it stays in the subscription map as "fired" until the app removes it from `subscriptions/1`.

### `Subscription.none/0`

Returns an empty list — explicit no-op:

```elixir
def subscriptions(_state), do: [Subscription.none()]
```

## Error handling and supervision

ExRatatui apps are supervised GenServers — the [Callback Runtime guide's Error Handling section](callback_runtime.md#error-handling-and-supervision) covers the common behaviour (raises in `render/2` skip the frame, raises in transition callbacks crash and restart the server, terminal restoration, disconnects, `:max_restarts`). With `init/1` for `mount/1` and `update/2` for `handle_event/2`/`handle_info/2`, it applies verbatim here. The reducer runtime adds two specifics:

  * **`Command.async/2` function raises:** The error is caught and the mapper receives an `{:error, reason}` tuple; errors in the mapper itself are wrapped with distinct `:mapper_*` tags. Either way the result is delivered to `update/2` as a normal `{:info, ...}` message — async commands always complete cleanly. `ExRatatui.Command.async/2` documents the full set of error shapes.

  * **Subscription timers after crash:** All timer references are lost on crash. After a supervisor restart, `subscriptions/1` re-declares the timers and the runtime re-arms them from scratch.

Use `ExRatatui.Runtime.enable_trace/2` to capture state transitions leading up to a crash for post-mortem debugging.

## Runtime inspection

`ExRatatui.Runtime` provides runtime introspection that works with both callback and reducer apps:

```elixir
{:ok, pid} = MyApp.TUI.start_link(name: nil)

# Snapshot of runtime metadata
snapshot = ExRatatui.Runtime.snapshot(pid)
snapshot.mode            #=> :reducer
snapshot.render_count    #=> 1
snapshot.subscription_count  #=> 1
snapshot.active_async_commands  #=> 0

# Enable in-memory tracing
:ok = ExRatatui.Runtime.enable_trace(pid, limit: 200)

# ... interact with the app ...

# Read trace events
events = ExRatatui.Runtime.trace_events(pid)

# Disable tracing
:ok = ExRatatui.Runtime.disable_trace(pid)
```

`ExRatatui.Runtime` documents the full snapshot field list.

### Synthetic event injection

`ExRatatui.Runtime.inject_event/2` delivers a synthetic terminal event through the same runtime transition path as polled input. This is the primary tool for testing supervised apps under `test_mode`:

```elixir
event = %ExRatatui.Event.Key{code: "up", modifiers: [], kind: "press"}
:ok = ExRatatui.Runtime.inject_event(pid, event)
```

## Running over transports

Reducer apps work across all transports with zero code changes — exactly like callback apps. See [Running Over Transports](callback_runtime.md#running-over-transports) in the Callback Runtime guide; everything there (including the `:local`-only `mouse_capture` / `focus_events` opts) applies unchanged.

## Testing

The basics are the same as for callback apps — `test_mode: {w, h}`, `name: nil`, and `ExRatatui.Runtime.inject_event/2`; see [Testing](callback_runtime.md#testing) in the Callback Runtime guide. The reducer-specific part is asserting on subscriptions:

```elixir
test "subscription fires tick message" do
  {:ok, pid} = MyApp.TUI.start_link(name: nil, test_mode: {40, 10})

  snapshot = ExRatatui.Runtime.snapshot(pid)
  assert snapshot.subscription_count == 1

  # Send the tick message directly instead of sleeping through a real
  # interval — same update/2 path, no flakiness. :sys.get_state/1 blocks
  # until the message has been processed.
  send(pid, :tick)
  _ = :sys.get_state(pid)

  snapshot = ExRatatui.Runtime.snapshot(pid)
  assert snapshot.render_count >= 2

  GenServer.stop(pid)
end
```

## Examples

  * [`examples/basics/reducer_counter_app.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/basics/reducer_counter_app.exs) — simple reducer-driven counter with subscriptions
  * [`switchyard`](https://github.com/nshkrdotcom/switchyard) — full-featured workbench exercising command batching, async effects, subscription reconciliation, runtime snapshots, trace toggles, `render?: false` quiet polling, distributed attach, and row-scrolled WidgetList (see [`full_featured_workbench.exs`](https://github.com/nshkrdotcom/switchyard/blob/main/examples/full_featured_workbench.exs) and the [reducer app entrypoint](https://github.com/nshkrdotcom/switchyard/blob/main/apps/terminal_workbench_tui/lib/switchyard/tui/app.ex))
  * [`phoenix_ex_ratatui_example`](https://github.com/mcass19/phoenix_ex_ratatui_example) — Phoenix app with a reducer-runtime stats TUI using `Command.async`, `Command.send_after`, `Command.batch`, and `Subscription.interval`, served over SSH and Erlang distribution alongside a public LiveView chat room
  * [`nerves_ex_ratatui_example`](https://github.com/mcass19/nerves_ex_ratatui_example) — Nerves firmware with a reducer-runtime system monitor using `Command.async` and `Subscription.interval`, reachable over SSH subsystems and Erlang distribution

## Related

  * `ExRatatui.App` — behaviour module
  * `ExRatatui.Command` — command constructors
  * `ExRatatui.Subscription` — subscription constructors
  * `ExRatatui.Runtime` — runtime inspection API
  * [Callback Runtime](callback_runtime.md) — alternative runtime with separate event/info callbacks
  * [Building UIs](../core/building_uis.md) — widgets, layout, styles, and events
  * [Running TUIs over SSH](../transports/ssh_transport.md) — SSH transport
  * [Running TUIs over Erlang Distribution](../transports/distributed_transport.md) — distribution transport
