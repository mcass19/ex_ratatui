# Rendering to non-terminal surfaces with `CellSession`

`ExRatatui.Session` is the right primitive when whatever consumes your TUI speaks ANSI — a real terminal, an SSH channel, a TCP socket on the other end of a raw-mode client. It encodes the rendered frame as escape sequences and hands them to the transport.

`ExRatatui.CellSession` is the right primitive when the consumer is **not** a terminal: a Phoenix LiveView painting `<span>`s into the DOM, an embedded device rasterising glyphs to a 1bpp framebuffer, a screenshot tool dumping a frame to PNG/SVG, any future renderer for displays that don't accept ANSI. These consumers want the **rendered cell buffer** — `(symbol, fg, bg, modifiers, skip)` per cell — not bytes. `CellSession` exposes that buffer directly, skipping the ANSI encode/decode round-trip and the client-side terminal emulator that ANSI implies.

## Session vs CellSession at a glance

| | `Session` | `CellSession` |
|---|---|---|
| Backend | `CrosstermBackend<SharedWriter>` | `TestBackend` |
| Output | ANSI byte stream (`take_output/1`) | Cell buffer (`take_cells/1`, `take_cells_diff/1`) |
| Consumer | Terminal emulator (real or virtual) | Anything that walks structured cells |
| Touches OS tty? | No | No |
| Same draw API? | Yes — `draw/2` takes the same `[{widget, rect}]` |
| Same input parser? | Yes — `feed_input/2` is identical |
| Same lifecycle? | Yes — `new/2`, `resize/3`, `close/1`, etc. |

An `ExRatatui.App` can run on either without knowing the difference. Switching transports is a matter of which session type the transport constructs, not changes in the App.

## Quick start

```elixir
alias ExRatatui.CellSession
alias ExRatatui.CellSession.{Cell, Snapshot}
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph}

session = CellSession.new(40, 6)

paragraph =
  %Paragraph{
    text: "Hello from CellSession!",
    style: %Style{fg: :light_cyan, modifiers: [:bold]},
    alignment: :center,
    block: %Block{title: " demo ", borders: [:all], border_type: :rounded}
  }

:ok = CellSession.draw(session, [{paragraph, %Rect{x: 0, y: 0, width: 40, height: 6}}])

%Snapshot{width: 40, height: 6, cells: cells} = CellSession.take_cells(session)

CellSession.close(session)
```

`cells` is a list of `%Cell{}` structs in row-major order:

```elixir
%ExRatatui.CellSession.Cell{
  row: 1, col: 14, symbol: "H",
  fg: :light_cyan, bg: :reset,
  modifiers: [:bold], skip: false
}
```

That's the whole API at the snapshot level. See the [`cell_dump.exs`](../examples/cell_session/cell_dump.exs) example for a tiny end-to-end script that paints a `Paragraph`, walks the snapshot, and prints it.

## The cell shape

Each cell carries:

| Field | Type | Notes |
|---|---|---|
| `:row` | `non_neg_integer()` | Zero-indexed (y in ratatui terms) |
| `:col` | `non_neg_integer()` | Zero-indexed (x in ratatui terms) |
| `:symbol` | `String.t()` | Grapheme cluster — usually one character, may be multi-codepoint (CJK, emoji, combining marks) |
| `:fg` | `t:ExRatatui.Style.color/0` | `:reset` means "consumer's default" — terminal default, CSS default, "ink" on a 1-bit display |
| `:bg` | Same | Same conventions |
| `:modifiers` | `[t:ExRatatui.Style.modifier/0]` | Stable canonical order: `:bold, :dim, :italic, :underlined, :crossed_out, :reversed`. Equality with `==` works without normalising |
| `:skip` | `boolean()` | ratatui's "do not render this cell" hint, used by widgets that overlay (`Popup`). Renderers should treat `skip: true` as transparent |

### Wide graphemes (CJK, emoji)

A two-cell-wide grapheme lands in its **leading cell only**. The following cell stays at its prior content (typically `" "`):

```
Cells for "中a" painted at (0, 0):
  (0, 0) symbol: "中"
  (1, 0) symbol: " "      # the continuation slot — left at default
  (2, 0) symbol: "a"
```

## Snapshots vs diffs

`take_cells/1` returns a full `%Snapshot{}` with every cell. Use it for the initial paint after a fresh client connects, one-off screenshots and exports, regression test fixtures, and debugging mid-stream — it is **stateless** and does not touch the diff baseline.

`take_cells_diff/1` returns a `%Diff{}` with only the cells that changed since the previous diff call. Three cases produce a "full" payload (every cell appears as an op): the very first call after constructing the session (no prior baseline), a `resize/3` between calls (the prior baseline is no longer a valid comparison reference), and a closed-then-reopened session (`close/1` wipes the baseline). After that, ops typically cover only the small fraction of cells that actually changed.

```elixir
session = CellSession.new(80, 24)

# Frame 0 — first call returns the full grid.
:ok = CellSession.draw(session, frame_0_widgets())
diff = CellSession.take_cells_diff(session)
length(diff.ops)  #=> 80 * 24 = 1920

# Frame 1 — typical small redraw.
:ok = CellSession.draw(session, frame_1_widgets())
diff = CellSession.take_cells_diff(session)
length(diff.ops)  #=> just the cells that changed

# No-op draw — diff is empty, no bytes to ship.
diff = CellSession.take_cells_diff(session)
diff.ops          #=> []
```

The op shape is identical to a snapshot's `Cell`. An op IS a cell at a position telling you "set this position to this content." Clearing a cell is just setting it to a default-styled space.

## Tight rects keep diffs small

`Paragraph` (and any styled widget) applies its `:style` to its **entire rect**, not just the painted text. A wide paragraph rect turns every cell in the rect into a styled cell, and the next diff correctly reports all of them as changed:

```elixir
# Paint "X" red — but in a 5-wide rect.
paragraph = %Paragraph{text: "X", style: %Style{fg: :red}}
:ok = CellSession.draw(session, [{paragraph, %Rect{x: 0, y: 0, width: 5, height: 1}}])

diff = CellSession.take_cells_diff(session)
length(diff.ops)
#=> 5  — every cell in the rect is now `fg: :red`, even the empty spaces
```

For minimal diffs, keep styled rects tight to the content:

```elixir
:ok = CellSession.draw(session, [{paragraph, %Rect{x: 0, y: 0, width: 1, height: 1}}])
length(diff.ops)
#=> 1  — only the "X" cell
```

This is the same behaviour you'd get on an ANSI terminal — ratatui clears each cell in the rect to the paragraph's style. It just shows up directly in the diff payload here.

## Driving an `ExRatatui.App` over a CellSession

The runtime server accepts a `:cell_session` transport tag in two shapes — a 3-tuple for transports that only need to ship rendered diffs, and a 4-tuple that adds an `intent_writer_fn` channel for transports that consume App-emitted intents (LiveView navigation, custom workflows, …).

```elixir
# 3-tuple — frame-only transport. Intents from the App are silently dropped.
{:cell_session, %CellSession{} = cell_session, cell_writer_fn}

# 4-tuple — frame + intent transport.
{:cell_session, %CellSession{} = cell_session, cell_writer_fn, intent_writer_fn}
```

Both are 1-arity functions:

```elixir
cell_writer_fn = fn %CellSession.Diff{} = diff ->
  # Ship the diff to wherever your renderer lives — a LiveView socket,
  # a websocket, an in-process callback, etc.
  send(target_pid, {:render, diff})
  :ok
end

intent_writer_fn = fn intent ->
  # Map App-emitted intents to consumer-side actions. Vocabulary is
  # entirely up to you; the runtime forwards verbatim.
  send(target_pid, {:intent, intent})
  :ok
end
```

Then start the runtime:

```elixir
{:ok, server} =
  ExRatatui.Transport.start_server(
    mod: MyTUI,
    transport: {:cell_session, cell_session, cell_writer_fn, intent_writer_fn}
  )
```

On every render the runtime server calls `CellSession.draw/2`, then `CellSession.take_cells_diff/1`, then hands the resulting `%Diff{}` to `cell_writer_fn`. On every state transition where the App returned `intents: [...]`, the runtime walks the list and calls `intent_writer_fn` once per intent, in emission order. Intents from a `{:stop, state, intents: ...}` transition fire **before** the server exits, so a TUI returning `{:stop, state, intents: [{:redirect, "/login"}]}` reliably reaches the consumer before the linked-server EXIT propagates.

Apps stay portable across transports: a TUI that emits `{:redirect, path}` from a callback runs unchanged over both a 4-tuple `:cell_session` (intent dispatched) and a `:local` tty (intent silently dropped — there's nothing to navigate).

See [Runtime opts](`ExRatatui.App#module-runtime-opts`) on `ExRatatui.App` for the App-side return-shape, and `phoenix_ex_ratatui` for a working consumer that turns intents into `Phoenix.LiveView` actions.

## Performance notes

  - **`take_cells/1` allocates one `%Cell{}` per cell.** For an 80×24 grid that's ~1920 structs per call. Modern BEAM handles this in a few hundred microseconds. For tight loops, prefer the diff path.
  - **`take_cells_diff/1` clones the current ratatui buffer** to use as next-call baseline. A buffer of 1920 cells clones in well under a millisecond. The diff comparison itself is O(width × height) of structural cell equality.
  - **Cell encoding crosses the NIF boundary** as a list of tuples, one per cell. The Elixir wrapper then maps tuples to `%Cell{}` structs. Both are linear in the number of cells emitted, which the diff path keeps small in steady state.
  - **Always close sessions you don't need** with `close/1` — it deterministically drops the underlying ratatui terminal and the cached diff baseline rather than waiting for BEAM GC.

## Related

- [Building UIs](../core/building_uis.md) — the widget tree you pass to `draw/2` is the same one used by every other transport.
- [Custom Transports](custom_transports.md) — how to wrap a `CellSession` (or `Session`) in an `ExRatatui.Transport` so an `ExRatatui.App` can run on it.
- [Performance](../internals/performance.md) — once a frame budget gets tight, this guide covers what to look at.
- `ExRatatui.CellSession` — module docs for the wrapper API.
- `ExRatatui.CellSession.Cell` / `ExRatatui.CellSession.Snapshot` / `ExRatatui.CellSession.Diff` — the structured payload types.
- `ExRatatui.Session` — the ANSI-bytes sibling for terminal-shaped consumers.
- [`cell_dump.exs`](../examples/cell_session/cell_dump.exs) — minimal headless example walking a snapshot.
