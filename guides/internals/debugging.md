# Debugging

Terminal UIs are harder to debug than web apps — no devtools, no browser console, and a single `IO.inspect` in `render/2` will garble the output. This guide covers the tools ExRatatui gives you instead.

Three layers, from least invasive to most:

1. **Runtime snapshot** — one call returns everything the runtime knows about your app.
2. **Runtime trace** — opt-in in-memory log of every message, render, command, and subscription event.
3. **Headless buffer inspection** — render a frame to the test backend and dump the string.

## Runtime snapshot

`ExRatatui.Runtime.snapshot/1` is the quickest way to see what's going on. It works on any running `ExRatatui.App`:

```elixir
iex> {:ok, pid} = MyApp.TUI.start_link(name: nil)
iex> ExRatatui.Runtime.snapshot(pid)
%{
  mode: :callbacks,
  mod: MyApp.TUI,
  transport: :local,
  polling_enabled?: true,
  dimensions: {120, 40},
  render_count: 17,
  last_rendered_at: 1745152496789,  # System.system_time(:millisecond)
  subscription_count: 1,
  subscriptions: [%{id: :tick, kind: :interval, interval_ms: 1_000, fired?: true, active?: true}],
  active_async_commands: 0,
  trace_enabled?: false,
  trace_limit: 200,
  trace_events: []
}
```

Fields you'll use most:

- `:render_count` — did render actually run? If this stays flat, your transition returned `render?: false` or your event isn't reaching `handle_event/2`.
- `:dimensions` — the size the runtime thinks it has. Off if something grabbed the terminal before mount.
- `:subscriptions` — reducer-runtime only; shows which timers are active and whether they've fired at least once.
- `:active_async_commands` — `Command.async/2` calls currently running.
- `:polling_enabled?` — `false` under `test_mode`, `true` in real terminals. If it's unexpectedly `false`, you probably passed `test_mode` accidentally.

## Runtime trace

For questions like "why did state transition here?" or "what commands did that event produce?", turn on tracing:

```elixir
iex> :ok = ExRatatui.Runtime.enable_trace(pid)
iex> # ... interact with the app ...
iex> ExRatatui.Runtime.trace_events(pid)
[
  %{kind: :message, at_ms: 123456, details: %{source: :event, payload: %ExRatatui.Event.Key{code: "up", ...}}},
  %{kind: :render, at_ms: 123457, details: %{frame: %ExRatatui.Frame{width: 120, height: 40}, widget_count: 4}},
  %{kind: :command, at_ms: 123458, details: %{kind: :message, message: :refresh}},
  %{kind: :subscription, at_ms: 123500, details: %{action: :fire, id: :tick, kind: :interval}},
  ...
]
```

Each event is a map with `:kind`, `:at_ms` (monotonic ms), and `:details`. Kinds:

- `:message` — a message arrived. `source: :event` for terminal input, `source: :info` for mailbox messages.
- `:render` — `render/2` ran. Gives you the frame and the widget count it returned.
- `:command` — a `Command` was queued. Kind is `:message`, `:after`, or `:async`.
- `:subscription` — subscription lifecycle (`:start`, `:cancel`, `:fire`).

The buffer defaults to 200 events, oldest dropped first. Bump it for long sessions:

```elixir
ExRatatui.Runtime.enable_trace(pid, limit: 1_000)
```

Turn it off when done — traces cost memory per transition:

```elixir
ExRatatui.Runtime.disable_trace(pid)
```

**From inside a reducer-runtime `update/2`**, you can flip tracing per-transition via the runtime opts:

```elixir
def update({:event, %Event.Key{code: "?", modifiers: ["ctrl"]}}, state) do
  {:noreply, state, trace?: true}
end
```

Useful to capture a specific interaction without leaving tracing on forever.

### Reading a trace

A typical "button press → state change → re-render" sequence looks like:

```
:message  source: :event    payload: %Event.Key{code: "up"}
:command  kind: :message    message: :boot            # whatever your update returned
:render   widget_count: 4
```

If you see `:message` but no `:render`, either:

- The transition returned `render?: false`
- `render/2` raised (check logs and the server's exit status)

If you see multiple `:render` for one event, something in `handle_info/2` triggered another transition — common with subscriptions firing during the same scheduler slot.

## Buffer inspection as a dev tool

When you can't eyeball "is my widget actually there?", render to a headless test terminal and print the buffer:

```elixir
terminal = ExRatatui.init_test_terminal(80, 24)
:ok = ExRatatui.draw(terminal, my_widget_tree)
IO.puts(ExRatatui.get_buffer_content(terminal))
```

This works anywhere — dev console, IEx, inside a test, inside `terminate/2`. It strips styling and gives you the pure character grid. Great for layout bugs where borders don't line up or text gets clipped.

To capture a supervised app's scene mid-run, factor `render/2` so the scene-building is pure:

```elixir
def render(state, frame), do: scene(state, frame)
def scene(state, frame), do: [ ... ]
```

Then from IEx or a test:

```elixir
state = :sys.get_state(pid).user_state
frame = %ExRatatui.Frame{width: 80, height: 24}
scene = MyApp.TUI.scene(state, frame)

terminal = ExRatatui.init_test_terminal(80, 24)
:ok = ExRatatui.draw(terminal, scene)
IO.puts(ExRatatui.get_buffer_content(terminal))
```

You get a snapshot of what the user's seeing without touching their terminal.

## `dbg/1` inside callbacks

`dbg/1` is tempting in `render/2` but will destroy the display — anything written to stdout while raw mode is active garbles the output. Two options:

**Log instead of printing.** `Logger.debug/1` goes to configured log backends, not the terminal. In dev, route it to a file:

```elixir
# config/dev.exs
config :logger, :default_handler, config: %{file: ~c"log/dev.log"}
```

**Use `dbg` in `handle_event/2` only when the app won't render afterwards.** If the event ends with `{:stop, state}`, stdout output is safe because the terminal gets restored during shutdown.

For interactive debugging, prefer `Runtime.snapshot/1` or the trace — both are non-invasive.

## Common errors

### `{:terminal_init_failed, reason}` on startup

The server tried to initialize a real terminal but the process has no TTY. Happens when:

- Running `mix run` with stdin redirected or piped
- Starting a TUI from an IDE's non-interactive test runner
- Backgrounding a process that later tries to render

**Fix:** For tests, pass `test_mode: {width, height}`. For dev, run from a real terminal emulator (Ghostty, iTerm2, Alacritty, Windows Terminal). For production use over SSH, don't use `:local` — use `transport: :ssh` so the daemon handles PTY allocation per client.

### Terminal looks garbled, colors wrong

Your terminal emulator isn't reporting 256-color or true-color support. Most modern emulators are fine. Under `tmux` or `screen`, set `TERM=xterm-256color`. Some SSH clients strip the outer `TERM` — if colors are right locally but wrong over SSH, check the remote `echo $TERM`.

### SSH client hangs, shows nothing

Most SSH clients don't allocate a PTY by default. Connect with `-t`:

```sh
ssh -t demo@localhost -p 2222
```

Without it, the TUI has nowhere to render. See the [SSH guide](../transports/ssh_transport.md).

### `mix run examples/foo.exs` exits immediately

The script finished because stdin wasn't a TTY and `poll_event/1` returned without input. Run from a real terminal. For daemon-mode examples (SSH, distributed), use `--no-halt` so the VM stays up after the script returns:

```sh
mix run --no-halt examples/apps/system_monitor.exs --ssh
```

### Render works once, then freezes

Usually a long-running computation inside `render/2`. Terminal events keep queuing, but the render loop is blocked. Move the heavy work to `handle_event/2` / `update/2` (fine — runs between renders) or an async command (`Command.async/2` in reducer runtime, `Task.Supervisor.async_nolink/2` in callback). See [Performance](performance.md).

### Runtime stops on its own with `{:stop, reason}`

Check the logs — an exception in any callback crashes the server. The generated `child_spec` uses `restart: :transient`, so the supervisor restarts the app after an abnormal exit but leaves it down after a clean `{:stop, state}`. In tests, `start_supervised!` propagates the crash into the test.

### I force-killed a TUI and now my shell is broken

If a TUI crashes without running `terminate/2` (SIGKILL, a kernel OOM, a disconnected SSH session), the terminal can be left in raw mode — characters don't echo, the cursor vanishes, or output wraps oddly. Restore it from the dazed shell:

```sh
reset      # full terminal reset — safest
stty sane  # lighter: restores line discipline without clearing
```

Both are safe to type blind. Under supervised runs this is rare because `terminate/2` restores the terminal on any `:normal`, `:shutdown`, or exception exit — but it can't fire if the BEAM itself is killed.

## Rust NIF rebuilds

If you're editing the native code under `native/ex_ratatui/`:

```sh
rm -rf _build
EX_RATATUI_BUILD=1 mix compile
EX_RATATUI_BUILD=1 mix test
```

The `rm -rf _build` is important — stale BEAM artifacts reference the old NIF image and your Rust changes won't take effect. Prepend `EX_RATATUI_BUILD=1` to *every* mix command until you stop editing Rust, otherwise mix falls back to precompiled binaries and silently ignores your edits.

Symptoms of a stale NIF:

- Adding a new NIF function and getting `UndefinedFunctionError`
- Changing a Rust signature and seeing the old behavior
- Compile succeeds but tests use old binary

## Where to go next

- **[Testing](testing.md)** — structured assertions with `Runtime.inject_event/2` and the test backend.
- **[Performance](performance.md)** — `Runtime.enable_trace/2` as a timing tool with `at_ms` timestamps.
- **`ExRatatui.Runtime`** module docs — full shape of every snapshot field.
