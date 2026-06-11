# Performance

Most ExRatatui apps don't need performance tuning — `render/2` runs fast, the default 16ms poll gives ~60fps, and cell-level diffing keeps network output tight over SSH. But once your app grows a thousand-row list, a tick-driven dashboard, or a dozen widgets recomputed every frame, the tradeoffs matter.

This guide covers the knobs, in order of impact.

## The render loop

When you run an `ExRatatui.App`, the server loop looks like this:

1. Poll the terminal for an event on the DirtyIo scheduler (non-blocking against other BEAM processes).
2. Receive an event, `handle_info` message, subscription firing, or async command result.
3. Run the matching callback (`handle_event/2`, `update/2`, etc.) to transition state.
4. If the transition opted in (default), call `render/2` to build the scene.
5. Hand the widget list to the Rust side, which diffs against the previous frame and writes only changed cells.

Every transition is a chance to re-render. If `render/2` is cheap and your transitions are sparse, you have headroom for a lot of widgets. If one of those is expensive, everything else pays.

## Skip renders you don't need — `render?: false`

Not every state change needs a visible update. Telemetry ticks, background cache refills, or bookkeeping transitions should skip the render:

```elixir
# Callback runtime
def handle_info({:metrics_refreshed, data}, state) do
  {:noreply, %{state | metrics: data}, render?: false}
end

# Reducer runtime
def update({:info, {:metrics_refreshed, data}}, state) do
  {:noreply, %{state | metrics: data}, render?: false}
end
```

`render?: false` keeps the new state but doesn't call `render/2` or push a frame. The next transition that does render will include the metrics update in the same frame.

Rule of thumb: if a state change doesn't change anything the user can see *right now*, skip the render. You can always force one by emitting a tick that *does* render.

## Keep `render/2` cheap

`render/2` can run many times per second. Anything expensive belongs in the transition, not the render.

**Derive in `handle_event` / `update`, not `render`.** Precompute sorted lists, grouped aggregates, filtered views once when they change — store the derived value in state. Let `render/2` read ready-made data.

```elixir
# Bad: sorts on every frame
def render(state, _frame) do
  items = Enum.sort_by(state.items, & &1.created_at)
  [ ... ]
end

# Good: sort once, cache, reuse
def handle_event(%Event.Key{code: "a"}, state) do
  items = [new_item(state) | state.items]
  sorted = Enum.sort_by(items, & &1.created_at)
  {:noreply, %{state | items: items, sorted: sorted}}
end

def render(state, _frame) do
  [ ... use state.sorted ... ]
end
```

**No I/O in `render/2`.** File reads, network calls, `Process.get/0`, `:ets.lookup/2` — move them out. Even local ETS adds per-frame overhead at 60fps.

**Avoid allocating large binaries from scratch on every frame.** If you build a huge formatted string that rarely changes, cache it in state too. Garbage collection on the render path is the tax you pay later.

**Widget structs are cheap to allocate, expensive to over-nest.** A widget list with thousands of `Span` structs for one line is fine; a `List` with twenty thousand items isn't — use the next section.

## Large trees: scrolling containers

Rendering a `%List{items: one_million_rows}` means encoding every row across the NIF boundary on every frame. Don't do that. Options:

**`%WidgetList{}`** — heterogeneous scrollable container with row clipping. You pass `{widget, height}` tuples plus a `scroll_offset`. Only visible rows are encoded in the output:

```elixir
%WidgetList{
  items: Enum.map(state.items, &{%Paragraph{text: &1}, 1}),
  scroll_offset: state.scroll_offset,
  selected: state.selected
}
```

For long homogeneous lists, slice yourself before passing to `%List{}`:

```elixir
visible = Enum.slice(state.items, state.scroll_offset, 20)
%List{items: visible, selected: state.selected - state.scroll_offset}
```

20 items cross the NIF boundary per frame instead of a million. You manage the viewport in state.

**Avoid re-allocating item lists on every frame.** If `state.items` doesn't change, `render/2` should reuse it verbatim, not `Enum.map` over it to "freshen" the structs.

## Poll interval

The default `poll_interval: 16` targets ~60fps. Every 16ms the server wakes on the DirtyIo scheduler and checks for terminal input. Two directions to tune:

- **Higher (e.g. `poll_interval: 33` → ~30fps)** — cuts CPU for idle apps. Input feels a touch laggier.
- **Lower (e.g. `poll_interval: 8`)** — snappier input response for games or typing-heavy UIs. More CPU.

```elixir
{:ok, _} = MyApp.TUI.start_link(poll_interval: 33)
```

Applies only to the `:local` transport. Over SSH, the daemon buffers and dispatches at its own pace. Over distribution, the client polls locally — set `poll_interval` in `Distributed.attach/3` options.

Remember this is just the *poll*, not the render cap. Rendering happens per-transition regardless of interval.

## Subscriptions (reducer runtime)

`Subscription.interval/3` is efficient — the runtime reconciles subscriptions after each transition, firing only what's due, starting new timers when a subscription appears, and canceling ones that disappear. That's the point: you get declarative timers without manually managing `Process.send_after` state.

Performance notes:

- **Short intervals still cost messages.** A 16ms subscription is 60 messages/sec plus 60 renders (unless you pair with `render?: false`). Prefer second-or-longer intervals for dashboards.
- **Subscriptions are pure by id.** Changing just the `:interval_ms` of an existing subscription id restarts the timer. Changing the id tears the old one down and starts fresh.
- **Conditional subscriptions.** Return `[]` (or omit from the list) when you don't need a timer — the runtime cancels it. This is the idiomatic way to "pause" a ticker: toggle a flag in state, check it in `subscriptions/1`, return the list conditionally.

```elixir
def subscriptions(%{paused: true}), do: []
def subscriptions(_state), do: [Subscription.interval(:tick, 1_000, :tick)]
```

## Async effects

Never block the runtime. A synchronous HTTP call in `handle_event/2` freezes the UI until it returns. Two escape hatches:

**Reducer runtime — `Command.async/1`:**

```elixir
def update({:event, %Event.Key{code: "r"}}, state) do
  command = Command.async(fn -> HTTPoison.get!("https://api.example.com/data") end, :data_loaded)
  {:noreply, state, commands: [command]}
end

def update({:info, {:data_loaded, response}}, state) do
  {:noreply, %{state | data: response.body}}
end
```

The runtime spawns a supervised task, keeps rendering normally, and delivers the result back through `update/2` when done.

**Callback runtime — `Task.Supervisor.async_nolink/2`:**

```elixir
def handle_event(%Event.Key{code: "r"}, state) do
  Task.Supervisor.async_nolink(MyApp.TaskSup, fn ->
    send(self(), :data_loaded)  # capture self() at the outer scope
  end)
  {:noreply, state}
end

def handle_info({ref, result}, state) when is_reference(ref) do
  Process.demonitor(ref, [:flush])
  {:noreply, %{state | data: result}}
end
```

`async_nolink` is important — without it, the task's crash would bring down the TUI. You supervise the Task.Supervisor separately in your app's supervision tree.

**Either way, don't use raw `Task.async/1` or `spawn/1` in production.** They're unsupervised — a crash leaks state or kills the app.

## Measuring

Two tools.

**`ExRatatui.Runtime.enable_trace/2`** gives you `:at_ms` timestamps on every message, render, command, and subscription. To time a render:

```elixir
ExRatatui.Runtime.enable_trace(pid)
# ... interact ...
events = ExRatatui.Runtime.trace_events(pid)

# Pair each :message with the next :render
events
|> Enum.chunk_every(2, 1, :discard)
|> Enum.filter(fn [a, b] -> a.kind == :message and b.kind == :render end)
|> Enum.map(fn [msg, render] -> render.at_ms - msg.at_ms end)
```

Good enough to spot outliers (one render that takes 40ms where the rest take 2ms).

**`:timer.tc/1`** is the standard microbenchmark for a single function. Use it on the scene-building logic you extracted from `render/2`:

```elixir
{time_us, _} = :timer.tc(fn -> MyApp.TUI.scene(state, frame) end)
IO.puts("scene build: #{time_us}µs")
```

If that's fast and the render is slow, the time's in the NIF — likely a giant widget list or deeply nested structs. See "Large trees" above.

## Transport considerations

- **Local transport** — render cost is whatever `render/2` takes plus the Rust diff, which writes only changed cells to the PTY. Cheap.
- **SSH transport** — every frame's diff crosses the SSH stream. Over slow links, prefer `render?: false` where possible and keep animated elements (throbbers, sparklines) small.
- **Distribution transport** — the app node encodes the widget list as BEAM terms and ships them to the client node. Large widget lists cost network bandwidth per frame. Same mitigation: skip renders, keep trees tight.
- **Cell-based consumers (`CellSession`)** — non-terminal renderers (LiveView, framebuffers) ship cells, not bytes. Use `take_cells_diff/1` instead of `take_cells/1` so steady-state frames carry only changed cells, and keep styled rects tight (a styled `Paragraph` paints its style across the whole rect — every cell counts as changed). See [Rendering to Non-Terminal Surfaces](../transports/cell_session.md).

The same app module runs on all of them without changes; you tune the transport-specific knobs (`poll_interval`, subscription cadence) at `start_link`.

## Where to go next

- **[Debugging](debugging.md)** — `enable_trace/2` for timing, `snapshot/1` for render counts.
- **[Reducer Runtime](../runtimes/reducer_runtime.md)** — full `Command` and `Subscription` API.
- **[Testing](testing.md)** — asserting `render_count` stays flat under `render?: false`.
- **[Rendering to Non-Terminal Surfaces](../transports/cell_session.md)** — diff-based cell shipping for LiveView and framebuffer consumers.
