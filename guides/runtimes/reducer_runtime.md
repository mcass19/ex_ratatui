# Reducer Runtime

The reducer runtime is an alternative way to build supervised TUI applications with `ExRatatui.App`. Inspired by The Elm Architecture, it routes all messages through a single `update/2` function and provides first-class primitives for side effects (`ExRatatui.Command`) and recurring timers (`ExRatatui.Subscription`).

This is the mode you want when:

  * Your TUI has async operations (HTTP calls, file I/O) and you want structured side-effect handling.
  * You need recurring timers that reconcile automatically when state changes.
  * You prefer a single message path over separate `handle_event` and `handle_info` callbacks.
  * You want built-in runtime inspection and tracing for debugging.

For simpler apps that don't need commands or subscriptions, see the [Callback Runtime](callback_runtime.md) guide.

## Quick Start

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

Add it to your supervision tree or run directly:

```elixir
children = [{MyApp.TUI, []}]
Supervisor.start_link(children, strategy: :one_for_one)
```

## Callbacks

| Callback | Required | Description |
|----------|----------|-------------|
| `init/1` | No | Called once on startup. Return `{:ok, state}` or `{:ok, state, opts}`. Defaults to `{:ok, %{}}` |
| `render/2` | Yes | Called after every state change. Return `[{widget, rect}]` |
| `update/2` | No | Receives `{:event, event}` or `{:info, message}`. Return `{:noreply, state}`, `{:noreply, state, opts}`, or `{:stop, state}`. Defaults to `{:noreply, state}` |
| `subscriptions/1` | No | Called after each state transition. Return a list of `Subscription` structs. Defaults to `[]` |
| `terminate/2` | No | Called on shutdown. Default is a no-op |

### The Message Path

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

### Runtime Options

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

### Intents

An intent is an arbitrary term — ex_ratatui never inspects it. The runtime forwards each intent your callbacks emit to the transport's `intent_writer_fn` in the order they were emitted. The vocabulary is consumer-defined: `phoenix_ex_ratatui` recognises `{:navigate, path}`, `{:patch, path}`, `{:redirect, path}`, and `{:redirect, [external: url]}`, dispatching them to the equivalent `Phoenix.LiveView` action.

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

Subscriptions are recurring or one-shot timers declared in `subscriptions/1`. The runtime reconciles them after each state transition — diffing by stable ID so you don't need to manage timer references manually.

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

## Error Handling and Supervision

ExRatatui apps are supervised GenServers — standard OTP fault tolerance applies. The reducer runtime adds a few specifics:

  * **`init/1` raises or returns `{:error, reason}`:** The server stops and the supervisor handles the restart. For SSH and distributed transports, the session is cleaned up and the client sees the connection close.

  * **`render/2` raises:** The error is logged and the frame is skipped — the server continues running with the previous screen content.

  * **`update/2` raises:** The server crashes and the supervisor restarts it. A fresh `init/1` starts from scratch — all subscriptions are re-established.

  * **`Command.async/2` function raises:** The error is caught and the mapper receives `{:error, {:exception, message}}`. If the mapper itself raises, the runtime wraps that into `{:error, {:mapper_exception, message}}`. In both cases, the result is delivered to `update/2` as a normal `{:info, ...}` message — async commands always complete cleanly.

  * **Subscription timers after crash:** All timer references are lost on crash. After a supervisor restart, `subscriptions/1` re-declares the timers and the runtime re-arms them from scratch.

  * **Terminal restoration:** On local transport, the terminal is automatically restored via the Rust ResourceArc finalizer when the reference is garbage collected.

  * **SSH/distributed disconnection:** The server detects the disconnect via monitors and shuts down cleanly, calling `terminate/2`.

For production deployments, set appropriate `:max_restarts` and `:max_seconds` on your supervisor to prevent restart loops. Use `ExRatatui.Runtime.enable_trace/2` to capture state transitions leading up to a crash for post-mortem debugging.

## Runtime Inspection

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

The snapshot includes:

  * `mode`, `mod`, and `transport`
  * `dimensions` and `polling_enabled?` (`false` under `test_mode`)
  * `render_count` and `last_rendered_at`
  * `subscription_count` and `subscriptions` (with `id`, `kind`, `fired?`, `active?`)
  * `active_async_commands`
  * `trace_enabled?`, `trace_limit`, and `trace_events`

### Synthetic Event Injection

`ExRatatui.Runtime.inject_event/2` delivers a synthetic terminal event through the same runtime transition path as polled input. This is the primary tool for testing supervised apps under `test_mode`:

```elixir
event = %ExRatatui.Event.Key{code: "up", modifiers: [], kind: "press"}
:ok = ExRatatui.Runtime.inject_event(pid, event)
```

## Running Over Transports

Reducer apps work across all three transports with zero code changes — exactly like callback apps:

```elixir
children = [
  {MyApp.TUI, []},                                    # local TTY
  {MyApp.TUI, transport: :ssh, port: 2222, ...},      # remote over SSH
  {MyApp.TUI, transport: :distributed}                 # remote over distribution
]
```

See the [Running TUIs over SSH](../transports/ssh_transport.md) and [Running TUIs over Erlang Distribution](../transports/distributed_transport.md) guides for transport-specific setup.

## Testing

```elixir
test "increments count on up key" do
  {:ok, pid} = MyApp.TUI.start_link(name: nil, test_mode: {40, 10})

  event = %ExRatatui.Event.Key{code: "up", modifiers: [], kind: "press"}
  :ok = ExRatatui.Runtime.inject_event(pid, event)

  snapshot = ExRatatui.Runtime.snapshot(pid)
  assert snapshot.render_count >= 2

  GenServer.stop(pid)
end

test "subscription fires tick message" do
  {:ok, pid} = MyApp.TUI.start_link(name: nil, test_mode: {40, 10})

  snapshot = ExRatatui.Runtime.snapshot(pid)
  assert snapshot.subscription_count == 1

  # Wait for at least one tick
  Process.sleep(1_100)

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
