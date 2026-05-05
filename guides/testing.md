# Testing

ExRatatui ships with a headless test backend so you can test TUIs in CI without a TTY. Tests run `async: true`, start in milliseconds, and assert against either the rendered character buffer or observable state transitions.

There are two testing levels:

1. **Widget-level** — render a widget to a headless terminal and assert on the buffer string. Good for widget authors, visual regressions, and layout checks.
2. **App-level** — start a supervised `ExRatatui.App` under `test_mode`, drive it with synthetic events, and assert on runtime state or app-emitted messages. Good for end-to-end interaction tests.

Both work together. Most apps need a handful of each.

## Widget-level: the headless backend

The core APIs are `ExRatatui.init_test_terminal/2`, `ExRatatui.draw/2`, and `ExRatatui.get_buffer_content/1`. A round-trip fits in one test:

```elixir
defmodule MyApp.WidgetTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  test "renders a styled paragraph inside a block" do
    terminal = ExRatatui.init_test_terminal(40, 10)

    widget = %Paragraph{
      text: "Hello!",
      style: %Style{fg: :green, modifiers: [:bold]},
      alignment: :center,
      block: %Block{title: " Greet ", borders: [:all]}
    }

    :ok = ExRatatui.draw(terminal, [{widget, %Rect{x: 0, y: 0, width: 40, height: 10}}])

    content = ExRatatui.get_buffer_content(terminal)

    assert content =~ "Hello!"
    assert content =~ "Greet"
  end
end
```

`get_buffer_content/1` returns the visible characters as a multi-line string, stripped of styling. That's usually what you want for assertions — but if you need exact column placement, the string is newline-delimited at the backend's width, so `String.split(content, "\n") |> Enum.at(row)` gets you one row.

Each test terminal is independent — no global state, nothing to clean up. `async: true` tests sharing a schema are safe.

## App-level: supervised apps under `test_mode`

When you start any `ExRatatui.App` with `test_mode: {width, height}`:

- The server boots against the headless backend instead of the real terminal
- Live terminal input polling is disabled (so ambient TTY events don't leak into your test)
- Everything else — `mount/1`, `render/2`, `handle_event/2`, commands, subscriptions — runs normally

You drive input with `ExRatatui.Runtime.inject_event/2` and assert against either the runtime snapshot or messages your app sends to a passed-in `test_pid`.

### Pattern 1: assert via runtime snapshot

```elixir
defmodule MyApp.CounterTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event
  alias ExRatatui.Runtime

  test "up arrow increments the counter" do
    pid = start_supervised!({MyApp.Counter, name: nil, test_mode: {40, 10}})

    :ok = Runtime.inject_event(pid, %Event.Key{code: "up", kind: "press"})
    :ok = Runtime.inject_event(pid, %Event.Key{code: "up", kind: "press"})

    assert %{render_count: n} = Runtime.snapshot(pid)
    assert n >= 2
  end
end
```

`start_supervised!/1` (from ExUnit) guarantees the server is cleaned up at the end of the test — always use it over bare `start_link/1`.

`Runtime.snapshot/1` returns a map with `render_count`, `dimensions`, `subscriptions`, `active_async_commands`, and more. See `ExRatatui.Runtime` for the full shape.

### Pattern 2: assert via a `test_pid`

For richer assertions, your app can send messages to a pid passed through mount opts:

```elixir
defmodule MyApp.Counter do
  use ExRatatui.App

  @impl true
  def mount(opts) do
    {:ok, %{count: 0, test_pid: Keyword.get(opts, :test_pid)}}
  end

  @impl true
  def handle_event(%ExRatatui.Event.Key{code: "up"}, state) do
    state = %{state | count: state.count + 1}
    if state.test_pid, do: send(state.test_pid, {:count_changed, state.count})
    {:noreply, state}
  end

  # ...
end
```

Then:

```elixir
test "tracks count over multiple presses" do
  pid =
    start_supervised!(
      {MyApp.Counter, name: nil, test_pid: self(), test_mode: {40, 10}}
    )

  :ok = Runtime.inject_event(pid, %Event.Key{code: "up", kind: "press"})
  assert_receive {:count_changed, 1}, 500

  :ok = Runtime.inject_event(pid, %Event.Key{code: "up", kind: "press"})
  assert_receive {:count_changed, 2}, 500
end
```

This hook is entirely in your app's code — no framework plumbing. The `test_pid` is just another mount option; production runs don't pass one, so `state.test_pid` is `nil` and the `send` is a no-op.

### Pattern 3: assert via `:sys.get_state`

For quick state inspection in tests, `:sys.get_state/1` works on any GenServer, including the ExRatatui server. The returned struct's `:user_state` field holds your app's state:

```elixir
server_state = :sys.get_state(pid)
assert server_state.user_state.count == 2
```

Useful in a pinch, but prefer `Runtime.snapshot/1` or a `test_pid` when the test should survive refactors.

## Testing event transitions

Key, mouse, and resize events all work the same way:

```elixir
# Key press
%ExRatatui.Event.Key{code: "enter", kind: "press"}
%ExRatatui.Event.Key{code: "c", modifiers: [:ctrl], kind: "press"}

# Mouse
%ExRatatui.Event.Mouse{kind: :down, button: :left, column: 10, row: 5}

# Resize
%ExRatatui.Event.Resize{columns: 120, rows: 40}
```

Any of these can be passed to `inject_event/2`. A resize event triggers a fresh render at the new size — good for asserting responsive layout code.

## Testing `handle_info` and subscriptions

Callback-runtime `handle_info/2` callbacks receive regular messages — just `send(pid, message)` in your test. Tracing with `enable_trace` (see [Debugging](debugging.md)) captures `:info` sources if you need to see them.

For reducer-runtime subscriptions:

```elixir
pid = start_supervised!({MyApp.TUI, name: nil, test_mode: {40, 10}})

snapshot = Runtime.snapshot(pid)
assert length(snapshot.subscriptions) == 1
assert [%{id: :tick, kind: :interval, interval_ms: 1_000}] = snapshot.subscriptions
```

You can let a real interval fire (fine for short intervals in fast tests), or prefer driving the transition manually via `inject_event/2` and asserting the effect — tests are more deterministic without timing dependencies.

## Patterns

### Asserting text is visible

Widget-level: assert on `get_buffer_content/1`. App-level: the server renders into its internal test terminal, but the buffer isn't exposed for supervised apps today — assert via `test_pid` / snapshot instead, or extract the render logic into a pure function and test it separately:

```elixir
# In lib/my_app/tui.ex
def render(state, frame), do: scene(state, frame)
def scene(state, frame), do: [{paragraph_for(state), rect_for(frame)}]

# In test/my_app/tui_test.exs
test "renders count with positive styling" do
  terminal = ExRatatui.init_test_terminal(40, 10)
  scene = MyApp.TUI.scene(%{count: 42}, %ExRatatui.Frame{width: 40, height: 10})
  :ok = ExRatatui.draw(terminal, scene)
  assert ExRatatui.get_buffer_content(terminal) =~ "42"
end
```

Pulling `scene/2` out of `render/2` is a light refactor that pays for itself the first time you want a visual assertion.

### Asserting text in a specific region

```elixir
content = ExRatatui.get_buffer_content(terminal)
rows = String.split(content, "\n")
assert Enum.at(rows, 5) =~ "status: ok"
```

For column ranges use `binary_part/3` or `String.slice/2` on the row.

### Asserting absence

```elixir
refute content =~ "error"
```

### Asserting focus moved

If your app renders the focused region's border in a distinct color, that'll show up in the buffer. If you track focus explicitly in state, assert against `:sys.get_state(pid).user_state.focus`.

## Property-based invariants

Use `stream_data` to check invariants that should hold for any input — decoder round-trips, layout constraints, style coercion. The ExRatatui test suite uses this approach for event decoding, layout, style, and text coercion. See `test/property/` in the repo for patterns: generators → assertions over `StreamData.check_all/3` blocks → deterministic seeds on failure.

## Cross-transport parity

A single app module runs over local, SSH, or distribution transports. To verify a change doesn't regress one of them, the suite runs the same scenario against all three transports using a shared driver module. For your own apps, one focused local-transport test suite is usually enough — only add cross-transport tests when you've seen a transport-specific bug or are shipping a library meant to be transport-agnostic.

## Gotchas

**Avoid `Process.sleep/1`.** If you're waiting for an event to be processed, use `_ = :sys.get_state(pid)` — by the time that call returns, the server has handled every prior message. If you're waiting for a message, use `assert_receive {msg, ...}, timeout`.

**Avoid `Process.alive?/1` for synchronization.** Prefer `Process.monitor/1` + `assert_receive {:DOWN, ^ref, :process, ^pid, _reason}`.

**`async: true` + `test_mode`.** `test_mode` disables terminal polling specifically so async tests don't race ambient TTY events. If you see flaky tests touching real stdin, make sure every `start_link` / `start_supervised!` passes `test_mode: {w, h}`.

**Don't forget `name: nil`.** Tests that start a named app will collide with any other test running in parallel under the same name. Pass `name: nil` to skip registration — you can still address the server by its pid.

**Rust NIF rebuilds.** If you're editing the Rust side too, prepend `EX_RATATUI_BUILD=1` and clean `_build/` first — stale precompiled binaries mask your changes. See [Debugging](debugging.md#rust-nif-rebuilds).

## Asserting on structured cells

`get_buffer_content/1` strips styling. When you need to assert on **per-cell colors, modifiers, or exact positions** — visual regression suites, snapshot tests for non-terminal renderers — `ExRatatui.CellSession` exposes the rendered cells as Elixir structs:

```elixir
session = ExRatatui.CellSession.new(40, 10)
:ok = ExRatatui.CellSession.draw(session, [{widget, %Rect{x: 0, y: 0, width: 40, height: 10}}])
%ExRatatui.CellSession.Snapshot{cells: cells} = ExRatatui.CellSession.take_cells(session)

styled = Enum.find(cells, &(&1.symbol == "H"))
assert styled.fg == :green
assert :bold in styled.modifiers
```

See [Rendering to Non-Terminal Surfaces](cell_session.md) for the full cell shape and the diff path.

## Where to go next

- **[Debugging](debugging.md)** — `Runtime.enable_trace/2`, buffer inspection during development.
- **[Performance](performance.md)** — how `render?: false` affects render counts in tests.
- **[Rendering to Non-Terminal Surfaces](cell_session.md)** — `CellSession` for tests that need structured cells.
- **`ExRatatui.Runtime`** module docs — full shape of `snapshot/1`, `enable_trace/2`, `inject_event/2`.
