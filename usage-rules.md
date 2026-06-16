# ExRatatui Usage Rules

ExRatatui is Elixir bindings for the Rust [ratatui](https://ratatui.rs) terminal UI library, via Rustler NIFs. It builds rich terminal UIs that run on the BEAM's DirtyIo scheduler, so rendering never blocks application processes.

It is **not** the Rust ratatui API and **not** bubbletea. Widgets are plain Elixir structs (pure view descriptors), assembled each frame and handed to a draw/render function. There are no stateful widget objects that update in place.

## Choosing a runtime

Pick the runtime before writing any code — this is the single most important decision and the easiest to get wrong.

| Use | When | Shape |
|-----|------|-------|
| `ExRatatui.run/2` | Scripts, one-shots, examples, throwaway demos | A closure that draws and polls events itself |
| `use ExRatatui.App` | Supervised interactive apps (the default) | LiveView-style `mount/1`, `render/2`, `handle_event/2`, `handle_info/2` |
| `use ExRatatui.App, runtime: :reducer` | Apps wanting pure transitions, declarative timers, and managed side effects | `init/1`, `update/2`, `render/2`, `subscriptions/1` + `Command`/`Subscription` |

- The callback runtime is the default and fits most apps. Reach for the reducer runtime when modeling the app as `(msg, state) -> state` with `Command`-driven effects and `Subscription`-driven timers is worth the structure.
- Both `App` runtimes are supervised: add `{MyApp.TUI, opts}` to a supervision tree. Never hand-roll the loop with `run/2` for a long-lived interactive app.

## Core API shape

Canonical entry points for a raw `run/2` loop — match these signatures exactly, do not invent Rust- or bubbletea-shaped calls:

```elixir
# fun receives a terminal reference; terminal is restored on exit, even on raise
ExRatatui.run(fn terminal ->
  {width, height} = ExRatatui.terminal_size()

  # draw/2 takes a LIST of {widget_struct, %Rect{}} tuples — a bare widget draws nothing
  ExRatatui.draw(terminal, [
    {%ExRatatui.Widgets.Paragraph{text: "hi"},
     %ExRatatui.Layout.Rect{x: 0, y: 0, width: width, height: height}}
  ])

  ExRatatui.poll_event(60_000)
end, mouse_capture: false, focus_events: false)
```

- `run/2` — `run(fun, opts \\ [])`. `fun` is arity-1, receiving a terminal reference. Opts: `:mouse_capture` and `:focus_events`, both **default `false`** on the local transport — opt in explicitly when needed.
- `draw/2` — `draw(terminal, [{widget, %Rect{}}, ...])`. The rect, in absolute 0-based cell coordinates, says where to paint.
- `poll_event/1` — `poll_event(timeout_ms \\ 250)`. Returns an `ExRatatui.Event.*` struct, `nil` on timeout, or `{:error, reason}`.
- `terminal_size/0` — returns `{width, height}` (a tuple, not a `Rect`).
- `Layout.split/4` — `split(area, direction, constraints, opts \\ [])`. Returns a list of `%Rect{}` (one per constraint). Direction is `:horizontal | :vertical`; constraints are `{:percentage, n}`, `{:length, n}`, `{:min, n}`, `{:max, n}`, `{:ratio, num, den}`, `{:fill, weight}`.
- `%ExRatatui.Layout.Rect{x: 0, y: 0, width: 0, height: 0}` — placement is explicit; widgets do not auto-resize to the terminal.

In an `App`, `render/2` receives `(state, %ExRatatui.Frame{width:, height:})` and returns the **full** `[{widget, %Rect{}}]` list for the whole screen — describe the entire frame every time, never a partial delta. The runtime diffs cells.

## Widget index

All widgets are structs under `ExRatatui.Widgets.*` (a few have a companion data module under `ExRatatui.*`). Knowing what exists prevents reinventing it.

**Text and containers**
- `Paragraph` — wrapped/aligned text with an optional block frame
- `Block` — borders, titles (top/bottom, per-title alignment via `Block.Title`)
- `Clear` — clears a region (use under popups/overlays)

**Lists and tables**
- `List` — selectable item list
- `Table` — rows, columns, header, selection
- `WidgetList` — vertically stacked, scrollable list of primitive widgets

**Progress and activity**
- `Gauge` — ratio bar with label
- `LineGauge` — single-line ratio bar
- `Sparkline` — compact inline trend line
- `Throbber` — animated spinner

**Charts and drawing**
- `BarChart` — bars (`Bar`, `BarGroup` data modules)
- `Chart` — line/scatter datasets (`Chart.Axis`, `Chart.Dataset`)
- `Canvas` — freeform drawing (`Circle`, `Label`, `Line`, `Map`, `Points`, `Rectangle`)

**Navigation and selection**
- `Tabs` — horizontal tab bar
- `Scrollbar` — scroll position indicator
- `Calendar` — month grid
- `Checkbox` — toggle
- `Popup` — modal/overlay container
- `SlashCommands` — command palette (`SlashCommands.Command`)

**Input (stateful — NIF-backed)**
- `TextInput` — single-line editor; drive via `ExRatatui.text_input_*` helpers
- `Textarea` — multi-line editor; drive via `ExRatatui.textarea_*` helpers

**Rich / special**
- `Markdown` — rendered Markdown
- `Image` — image rendering (`ExRatatui.Image` decodes; Kitty/Sixel/iTerm2/halfblocks)
- `BigText` — oversized 8x8 pixel text (`ExRatatui.BigText`)
- `CodeBlock` — syntax-highlighted code (`ExRatatui.CodeBlock`)

**App-level helpers (not widgets)**
- `ExRatatui.Focus` — focus ring for multi-panel apps. `handle_key/2` consumes Tab/Shift+Tab and returns `{focus, key_or_nil}` (`nil` = consumed); register rects to get click-to-focus via `handle_mouse/2`; style with `focused?/2`. Pure data, no process — do not hand-roll focus tracking.
- `ExRatatui.Theme` — semantic color palette (eleven slots) with `default/0` / `light/0` constructors and `border_style/2` / `text_style/2` / `selection_style/1` helpers. Pure data threaded through render code — no globals, no automatic widget injection.
- `ExRatatui.CellSession` — render to a cell buffer instead of ANSI bytes (Phoenix LiveView, framebuffers, screenshots). Reach for it before parsing ANSI out of a `Session`.

Compose custom composite widgets in pure Elixir via the `ExRatatui.Widget` protocol — no Rust required. See the Custom Widgets guide.

## Anti-patterns and gotchas

Highest-value rules. The guides hold the full set; these are the ones agents get wrong most.

- **Key event fields are lowercase strings, never atoms — wrong values compile and silently never match.** The shape is `%Event.Key{code: "up", kind: "press", modifiers: ["ctrl"]}`. Character keys are their string value (`"a"`, `"1"`, `" "`); special keys include `"enter"`, `"esc"`, `"tab"`, `"back_tab"`, `"backspace"`, `"up"` / `"down"` / `"left"` / `"right"`, `"page_up"` / `"page_down"`, `"f1"`..`"f12"` — full table in `ExRatatui.Event.Key`. Mouse events use string `kind` / `button` the same way (`%Event.Mouse{kind: "down", button: "left", x: 0, y: 0}`).
- **Never call `draw/2` with a bare widget — pass `[{widget, %Rect{}}, ...]`.** A widget without a rect paints nothing.
- **Never treat a widget as stateful — rebuild the struct each frame.** Widgets are immutable view descriptors, not objects that mutate in place.
- **Never return a partial scene from `render/2` — return the whole screen.** The runtime diffs cells; the job is to describe the full frame.
- **Never create `TextInput`/`Textarea` state in `render/2` — create it once in `mount/1`/`init/1` and keep the ref in state.** Recreating it each render drops cursor position and typed text.
- **Never do I/O, HTTP, sorting, or large allocations in `render/2`.** It runs up to ~60fps; derive once in the transition callback and store the result in state.
- **Never make a blocking call in `handle_event/2`/`update/2`.** Use `ExRatatui.Command.async/2` (reducer) or `Task.Supervisor.async_nolink/2` (callback). A blocking call freezes the whole UI.
- **Always include a catch-all `handle_event(_event, state)` / `update(_msg, state)` returning `{:noreply, state}`.** Unmatched events otherwise crash the app.
- **Never `IO.inspect`/`IO.puts`/`dbg` to stdout while in raw mode** — it garbles the display. Log to a file via `Logger`, or use `Runtime.snapshot/1`.
- **Reducer `update/2` receives `{:event, event}` and `{:info, msg}`, never bare structs.** All input is routed through one `update/2`.
- **`commands:` and `render?:` runtime opts are designed for the reducer runtime.** They execute under the callback runtime too (command results land in `handle_info/2`), but idiomatic callback apps use `Process.send_after/3` or a supervised Task.
- **Never serve a TUI to remote users over the `:local` transport — use `transport: :ssh` or `:distributed`.** `:local` grabs the host tty and fails with `terminal_init_failed` where there is no TTY.
- **Never background or pipe stdin into a `mix run`/`iex` TUI example.** With no TTY it exits immediately or raises `terminal_init_failed`; run it in a real terminal emulator.
- **In tests, always pass `test_mode: {w, h}` and `name: nil`, and drive input with `ExRatatui.Runtime.inject_event/2`.** `test_mode` disables live TTY polling so `async: true` tests do not race; named apps collide across parallel tests.

## Going deeper

Full walkthroughs and the complete gotcha set live in the guides (hexdocs):

- Getting started — https://hexdocs.pm/ex_ratatui/getting_started.html
- Building UIs — https://hexdocs.pm/ex_ratatui/building_uis.html
- Callback runtime — https://hexdocs.pm/ex_ratatui/callback_runtime.html
- Reducer runtime — https://hexdocs.pm/ex_ratatui/reducer_runtime.html
- Custom widgets — https://hexdocs.pm/ex_ratatui/custom_widgets.html
- State machine patterns — https://hexdocs.pm/ex_ratatui/state_machines.html
- Testing — https://hexdocs.pm/ex_ratatui/testing.html
- Debugging — https://hexdocs.pm/ex_ratatui/debugging.html
- Performance — https://hexdocs.pm/ex_ratatui/performance.html
- Telemetry — https://hexdocs.pm/ex_ratatui/telemetry.html
- Transports — https://hexdocs.pm/ex_ratatui/transports.html
- Running over SSH — https://hexdocs.pm/ex_ratatui/ssh_transport.html
- Running over Erlang distribution — https://hexdocs.pm/ex_ratatui/distributed_transport.html
- Custom transports — https://hexdocs.pm/ex_ratatui/custom_transports.html
- Rendering to non-terminal surfaces (CellSession) — https://hexdocs.pm/ex_ratatui/cell_session.html
- Images — https://hexdocs.pm/ex_ratatui/images.html
- Paste and clipboard — https://hexdocs.pm/ex_ratatui/paste_and_clipboard.html
- Widgets cheatsheet — https://hexdocs.pm/ex_ratatui/widgets.html
