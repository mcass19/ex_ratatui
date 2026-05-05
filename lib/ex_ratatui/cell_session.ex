defmodule ExRatatui.CellSession do
  @moduledoc """
  A per-connection terminal session that surfaces ratatui's rendered
  cell buffer instead of ANSI bytes.

  Where `ExRatatui.Session` is the right primitive when the consumer
  speaks ANSI (a real terminal, an SSH channel, a TCP socket reading
  escape sequences), `CellSession` is the right primitive when the
  consumer is *not* a terminal — a Phoenix LiveView painting `<span>`s,
  an embedded device rasterising glyphs to a framebuffer, an SVG/PNG
  exporter, a screenshot tool. Those consumers want the post-render
  `Buffer` itself: per-cell `(symbol, fg, bg, modifiers, skip)` data
  they turn into pixels (or DOM, or vectors) themselves.

  The session itself is a deliberate near-mirror of `ExRatatui.Session`,
  with two changes:

    1. Backend is ratatui's `TestBackend` (in-memory `Buffer`, no ANSI
       emission) instead of `CrosstermBackend`.
    2. There is no `take_output/1` — the buffer *is* the output.
       Surface it via `take_cells/1` (full snapshot) or
       `take_cells_diff/1` (only changed cells since the last diff
       call).

  Everything else — input parsing, draw command shape, lifecycle,
  resize semantics — is the same. An `ExRatatui.App` doesn't know
  which session type is hosting it.

  ## Lifecycle

      session  = ExRatatui.CellSession.new(80, 24)
      :ok      = ExRatatui.CellSession.draw(session, [{paragraph, rect}])
      snap     = ExRatatui.CellSession.take_cells(session)
      diff     = ExRatatui.CellSession.take_cells_diff(session)
      events   = ExRatatui.CellSession.feed_input(session, "\\e[A")
      :ok      = ExRatatui.CellSession.resize(session, 100, 30)
      :ok      = ExRatatui.CellSession.close(session)

  Like `Session`, the struct holds a `t:reference/0` to a Rust-side
  `ResourceArc` and is freed on garbage collection. `close/1` is the
  deterministic version of the same cleanup and is idempotent.

  ## Snapshots vs diffs

  `take_cells/1` returns an `ExRatatui.CellSession.Snapshot` containing
  every cell — use it for the initial paint, screenshots, tests, or
  any time the consumer needs the full picture.

  `take_cells_diff/1` returns an `ExRatatui.CellSession.Diff` containing
  only the cells that changed since the previous diff call. The first
  call after construction (or after a resize, or after close+reopen)
  returns the full grid as ops — there's no prior baseline to diff
  against. After that, ops typically cover only the small fraction of
  cells that actually changed, dramatically reducing payload size for
  streaming consumers (Phoenix LiveView pushing frames over a websocket,
  embedded devices minimising SPI bandwidth).

  Snapshots and diffs can be freely interleaved — `take_cells/1` does
  not touch the diff baseline. A consumer can grab a snapshot for
  debugging mid-stream without disturbing the next `take_cells_diff/1`.

  ## Transport responsibilities

  Like `Session`, a `CellSession` does not own a socket and does no I/O
  of its own. The transport glue is responsible for:

    1. Calling `draw/2` whenever the app wants to repaint, then handing
       the result of `take_cells/1` (or `take_cells_diff/1`) to the
       wire — typically as JSON for a browser consumer, or as a packed
       binary for an embedded one.
    2. Feeding inbound transport bytes through `feed_input/2` and
       dispatching the returned `t:ExRatatui.Event.t/0` values to the
       app.
    3. Calling `resize/3` when the remote viewport changes size.
    4. Calling `close/1` when the connection ends.

  See [`guides/cell_session.md`](guides/cell_session.md) for end-to-end
  examples (LiveView, framebuffer, screenshot tools) and
  [`guides/custom_transports.md`](guides/custom_transports.md) for the
  `ExRatatui.Transport` contract a `CellSession`-backed transport plugs
  into.
  """

  alias ExRatatui.CellSession.{Diff, Snapshot}
  alias ExRatatui.Event
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native

  @enforce_keys [:ref]
  defstruct [:ref]

  @type t :: %__MODULE__{ref: reference()}

  @doc """
  Creates a new cell session at the given dimensions.

  No OS terminal state is touched — the session writes into an
  in-memory `TestBackend` buffer that callers drain via `take_cells/1`.
  Both dimensions must be at least `1`.

  ## Examples

      iex> session = ExRatatui.CellSession.new(80, 24)
      iex> ExRatatui.CellSession.size(session)
      {80, 24}
      iex> ExRatatui.CellSession.close(session)
      :ok
  """
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %__MODULE__{ref: Native.cell_session_new(width, height)}
  end

  @doc """
  Renders a list of `{widget, rect}` tuples into the session's terminal.

  Identical in shape to `ExRatatui.draw/2` and `ExRatatui.Session.draw/2`,
  but the rendered cells land in the `TestBackend`'s in-memory `Buffer`
  instead of being encoded to ANSI. Drain via `take_cells/1` or
  `take_cells_diff/1`.

  Returns `:ok` on success, or `{:error, reason}` if the session has
  been closed or a widget cannot be encoded.

  ## Examples

      iex> alias ExRatatui.Widgets.Paragraph
      iex> alias ExRatatui.Layout.Rect
      iex> session = ExRatatui.CellSession.new(20, 5)
      iex> rect = %Rect{x: 0, y: 0, width: 20, height: 5}
      iex> ExRatatui.CellSession.draw(session, [{%Paragraph{text: "hi"}, rect}])
      :ok
  """
  @spec draw(t(), [{ExRatatui.widget(), Rect.t()}]) :: :ok | {:error, term()}
  def draw(%__MODULE__{ref: ref}, widgets) when is_list(widgets) do
    commands = ExRatatui.Bridge.encode_commands!(widgets)
    Native.cell_session_draw(ref, commands)
  end

  @doc """
  Returns a full snapshot of the current cell buffer.

  The result is an `ExRatatui.CellSession.Snapshot` carrying the buffer
  dimensions and every cell as a `Cell` struct, in row-major order
  (`(0,0), (1,0), ..., (W-1,0), (0,1), ...`). For a fresh session that
  has never been drawn into, every cell is at its default
  (`symbol: " ", fg: :reset, bg: :reset, modifiers: [], skip: false`).

  This call is **stateless**: it does not touch the diff baseline used
  by `take_cells_diff/1`. Snapshots and diffs can be freely
  interleaved.

  Returns `{:error, reason}` if the session has been closed.
  """
  @spec take_cells(t()) :: Snapshot.t() | {:error, term()}
  def take_cells(%__MODULE__{ref: ref}) do
    case Native.cell_session_take_cells(ref) do
      {:error, _} = err -> err
      payload -> Snapshot.from_native(payload)
    end
  end

  @doc """
  Returns the cells that changed since the last `take_cells_diff/1` call.

  The result is an `ExRatatui.CellSession.Diff` carrying the buffer
  dimensions and a list of `Cell` ops — same shape as a snapshot's
  cells, just a smaller subset. Three cases produce a "full" payload
  where every cell appears as an op:

    * the very first call after constructing the session
    * a `resize/3` between calls (prior baseline is no longer comparable)
    * the session was closed and reopened (close wipes the baseline)

  The session caches a clone of the current buffer on every call,
  so subsequent calls compare against that snapshot. Cells are
  compared structurally — two cells with identical visual output
  (same symbol, fg, bg, modifiers, skip) never appear in the diff.
  Style-only changes do show up.

  Returns `{:error, reason}` if the session has been closed.
  """
  @spec take_cells_diff(t()) :: Diff.t() | {:error, term()}
  def take_cells_diff(%__MODULE__{ref: ref}) do
    case Native.cell_session_take_cells_diff(ref) do
      {:error, _} = err -> err
      payload -> Diff.from_native(payload)
    end
  end

  @doc """
  Feeds raw transport bytes through the session's ANSI input parser.

  Returns a list of decoded `t:ExRatatui.Event.t/0` structs in the
  order the parser produced them. Bytes that only partially form an
  escape sequence stay buffered inside the session — feed the next
  chunk and the parser will pick up where it left off. This is
  essential for any byte-stream transport that may chunk a single
  keystroke across multiple packets.

  Unlike `draw/2`, this still works after `close/1` — the input
  parser outlives the rendering terminal so a transport can drain
  trailing input bytes after deciding to tear down rendering.

  ## Examples

      iex> session = ExRatatui.CellSession.new(20, 5)
      iex> ExRatatui.CellSession.feed_input(session, "a")
      [%ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}]
  """
  @spec feed_input(t(), binary()) :: [Event.t()]
  def feed_input(%__MODULE__{ref: ref}, bytes) when is_binary(bytes) do
    ref
    |> Native.cell_session_feed_input(bytes)
    |> Enum.map(&ExRatatui.decode_event/1)
  end

  @doc """
  Resets the session's input parser, discarding any buffered partial
  escape sequence.

  Used by transports implementing an Esc timeout: after a bare `0x1B`
  with no follow-up bytes, the VTE state machine is stuck in the
  Escape state. Calling this drops that state so the next byte is
  parsed from Ground.

  ## Examples

      iex> session = ExRatatui.CellSession.new(20, 5)
      iex> ExRatatui.CellSession.reset_parser(session)
      :ok
  """
  @spec reset_parser(t()) :: :ok
  def reset_parser(%__MODULE__{ref: ref}) do
    Native.cell_session_reset_parser(ref)
  end

  @doc """
  Resizes the session's viewport to `width` x `height`.

  The next `draw/2` will render at the new dimensions, and the next
  `take_cells_diff/1` will return a full payload (the prior diff
  baseline is no longer comparable across a different area). Returns
  `{:error, reason}` if the session has been closed.

  ## Examples

      iex> session = ExRatatui.CellSession.new(20, 5)
      iex> :ok = ExRatatui.CellSession.resize(session, 100, 30)
      iex> ExRatatui.CellSession.size(session)
      {100, 30}
  """
  @spec resize(t(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def resize(%__MODULE__{ref: ref}, width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    Native.cell_session_resize(ref, width, height)
  end

  @doc """
  Returns the session's current `{width, height}`.

  ## Examples

      iex> session = ExRatatui.CellSession.new(80, 24)
      iex> ExRatatui.CellSession.size(session)
      {80, 24}
  """
  @spec size(t()) :: {pos_integer(), pos_integer()}
  def size(%__MODULE__{ref: ref}) do
    Native.cell_session_size(ref)
  end

  @doc """
  Closes the session, dropping its rendering terminal and any cached
  diff baseline.

  Idempotent — calling `close/1` more than once is safe and always
  returns `:ok`. After closing, `draw/2`, `take_cells/1`,
  `take_cells_diff/1`, and `resize/3` will return `{:error, _}`, but
  `feed_input/2` continues to work so a transport can drain trailing
  input bytes.

  ## Examples

      iex> session = ExRatatui.CellSession.new(20, 5)
      iex> ExRatatui.CellSession.close(session)
      :ok
      iex> ExRatatui.CellSession.close(session)
      :ok
  """
  @spec close(t()) :: :ok
  def close(%__MODULE__{ref: ref}) do
    Native.cell_session_close(ref)
  end
end
