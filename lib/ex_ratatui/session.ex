defmodule ExRatatui.Session do
  @moduledoc """
  A per-connection terminal session backed by an in-memory writer.

  Where `ExRatatui.run/1` and `ExRatatui.draw/2` are tied to the OS process'
  real tty (raw mode, alternate screen, `SIGWINCH`), a `Session` is a
  self-contained ratatui terminal whose output goes into a buffer and whose
  input arrives as raw bytes from a transport you control. That makes it
  the right primitive for serving a TUI over SSH, multiplexing several
  TUIs in one BEAM node, or any context where the "terminal" lives somewhere
  other than the local process.

  Sessions touch nothing on the host tty, so they are safe to create and
  drive concurrently from `async: true` tests, GenServers, or background
  tasks.

  ## Lifecycle

      session = ExRatatui.Session.new(80, 24)
      :ok     = ExRatatui.Session.draw(session, [{paragraph, rect}])
      bytes   = ExRatatui.Session.take_output(session)
      events  = ExRatatui.Session.feed_input(session, "\\e[A")
      :ok     = ExRatatui.Session.resize(session, 100, 30)
      :ok     = ExRatatui.Session.close(session)

  Each call is a thin wrapper over a Rust NIF, so a session is just an
  Elixir struct holding a `t:reference/0` to a `ResourceArc`. When the
  struct is garbage collected the underlying resource is freed; `close/1`
  is the deterministic version of the same cleanup and is idempotent.

  ## Transport responsibilities

  A session does not own a socket or do any I/O of its own. The transport
  glue is responsible for:

    1. Calling `draw/2` whenever the app wants to repaint, then handing the
       result of `take_output/1` to the wire.
    2. Feeding inbound transport bytes through `feed_input/2` and dispatching
       the returned `t:ExRatatui.Event.t/0` values to the app.
    3. Calling `resize/3` when the remote pty changes size.
    4. Calling `close/1` when the connection ends.

  See `ExRatatui.SSH` for an OTP `:ssh_server_channel`-based transport.

  If your consumer is **not** a terminal — a Phoenix LiveView painting
  `<span>` cells, an embedded framebuffer, a screenshot tool —
  `ExRatatui.CellSession` is the cell-buffer sibling. Same widget tree,
  same input parser, same lifecycle; `take_output/1` is replaced by
  `take_cells/1` and `take_cells_diff/1`. See
  [`guides/transports/cell_session.md`](guides/transports/cell_session.md).
  """

  alias ExRatatui.Event
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native

  @enforce_keys [:ref]
  defstruct [:ref]

  @type t :: %__MODULE__{ref: reference()}

  @doc """
  Creates a new session at the given dimensions.

  No OS terminal state is touched — the session writes into an in-memory
  buffer that the transport drains via `take_output/1`. Both dimensions
  must be at least `1`.

  ## Examples

      iex> session = ExRatatui.Session.new(80, 24)
      iex> ExRatatui.Session.size(session)
      {80, 24}
      iex> ExRatatui.Session.close(session)
      :ok
  """
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %__MODULE__{ref: Native.session_new(width, height)}
  end

  @doc """
  Renders a list of `{widget, rect}` tuples into the session's writer.

  Identical in shape to `ExRatatui.draw/2`, but the encoded ANSI bytes
  accumulate in the session's in-memory buffer instead of going to the
  real tty. Drain them with `take_output/1`.

  Returns `:ok` on success, or `{:error, reason}` if the session has been
  closed or a widget cannot be encoded.

  ## Examples

      iex> alias ExRatatui.Widgets.Paragraph
      iex> alias ExRatatui.Layout.Rect
      iex> session = ExRatatui.Session.new(20, 5)
      iex> ExRatatui.Session.draw(session, [{%Paragraph{text: "hi"}, %Rect{x: 0, y: 0, width: 20, height: 5}}])
      :ok
  """
  @spec draw(t(), [{ExRatatui.widget(), Rect.t()}]) :: :ok | {:error, term()}
  def draw(%__MODULE__{ref: ref}, widgets) when is_list(widgets) do
    commands = ExRatatui.Bridge.encode_commands!(widgets)
    Native.session_draw(ref, commands)
  end

  @doc """
  Drains the session's pending output bytes.

  Returns whatever ratatui has written into the in-memory buffer since the
  last drain — typically the bytes the transport should ship to the
  remote tty. The internal buffer is emptied as a side effect, so a
  follow-up call with no intervening `draw/2` returns `<<>>`.

  ## Examples

      iex> session = ExRatatui.Session.new(20, 5)
      iex> :ok = ExRatatui.Session.draw(session, [])
      iex> bytes = ExRatatui.Session.take_output(session)
      iex> byte_size(bytes) > 0
      true
      iex> ExRatatui.Session.take_output(session)
      ""
  """
  @spec take_output(t()) :: binary()
  def take_output(%__MODULE__{ref: ref}) do
    Native.session_take_output(ref)
  end

  @doc """
  Feeds raw transport bytes through the session's ANSI input parser.

  Returns a list of decoded `t:ExRatatui.Event.t/0` structs, in the order
  the parser produced them. Bytes that only partially form an escape
  sequence stay buffered inside the session — feed the next chunk and
  the parser will pick up where it left off. This is essential for SSH
  and any other byte-stream transport that may chunk a single keystroke
  across multiple packets.

  Unlike `draw/2`, this still works after `close/1` — the input parser
  outlives the rendering terminal so a transport can drain trailing
  input bytes after deciding to tear down rendering.

  ## Examples

      iex> session = ExRatatui.Session.new(20, 5)
      iex> ExRatatui.Session.feed_input(session, "a")
      [%ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}]
  """
  @spec feed_input(t(), binary()) :: [Event.t()]
  def feed_input(%__MODULE__{ref: ref}, bytes) when is_binary(bytes) do
    ref
    |> Native.session_feed_input(bytes)
    |> Enum.map(&ExRatatui.decode_event/1)
  end

  @doc """
  Resets the session's input parser, discarding any buffered partial
  escape sequence.

  Used by the SSH transport's Esc timeout: after a bare `0x1B` with no
  follow-up bytes, the VTE state machine is stuck in the Escape state.
  Calling this drops that state so the next byte is parsed from Ground.

  ## Examples

      iex> session = ExRatatui.Session.new(20, 5)
      iex> ExRatatui.Session.reset_parser(session)
      :ok
  """
  @spec reset_parser(t()) :: :ok
  def reset_parser(%__MODULE__{ref: ref}) do
    Native.session_reset_parser(ref)
  end

  @doc """
  Resizes the session's viewport to `width` x `height`.

  The next `draw/2` will paint at the new dimensions and the buffer will
  contain a clear-screen sequence the transport must forward. Returns
  `{:error, reason}` if the session has been closed.

  ## Examples

      iex> session = ExRatatui.Session.new(20, 5)
      iex> :ok = ExRatatui.Session.resize(session, 100, 30)
      iex> ExRatatui.Session.size(session)
      {100, 30}
  """
  @spec resize(t(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def resize(%__MODULE__{ref: ref}, width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    Native.session_resize(ref, width, height)
  end

  @doc """
  Returns the session's current `{width, height}`.

  ## Examples

      iex> session = ExRatatui.Session.new(80, 24)
      iex> ExRatatui.Session.size(session)
      {80, 24}
  """
  @spec size(t()) :: {pos_integer(), pos_integer()}
  def size(%__MODULE__{ref: ref}) do
    Native.session_size(ref)
  end

  @doc """
  Closes the session, dropping its rendering terminal.

  Idempotent — calling `close/1` more than once is safe and always
  returns `:ok`. After closing, `draw/2` and `resize/3` will return
  `{:error, _}`, but `feed_input/2` continues to work so a transport
  can drain any trailing input bytes.

  ## Examples

      iex> session = ExRatatui.Session.new(20, 5)
      iex> ExRatatui.Session.close(session)
      :ok
      iex> ExRatatui.Session.close(session)
      :ok
  """
  @spec close(t()) :: :ok
  def close(%__MODULE__{ref: ref}) do
    Native.session_close(ref)
  end

  @doc """
  Sets the terminal image protocol hint for this session.

  When an `%ExRatatui.Widgets.Image{}` is rendered with `protocol: :auto`,
  the renderer needs to know which terminal protocol the client supports
  (Kitty, Sixel, iTerm2, or Halfblocks). For a `Session` — which is what
  SSH and Distributed transports use under the hood — we can't probe the
  client terminal, so the caller declares it once with this function.

  Passing `:auto` clears the hint, restoring the default halfblocks
  fallback. Any other value is honored as the explicit protocol used to
  resolve `:auto` per image.

  This setting only affects images rendered with `protocol: :auto`.
  Explicit per-image protocol selections at `ExRatatui.Image.new/2` are
  always honored.

  ## Examples

      iex> session = ExRatatui.Session.new(20, 5)
      iex> ExRatatui.Session.set_image_protocol(session, :kitty)
      :ok
  """
  @spec set_image_protocol(t(), ExRatatui.Image.protocol()) :: :ok
  def set_image_protocol(%__MODULE__{ref: ref}, protocol)
      when protocol in [:auto, :halfblocks, :kitty, :sixel, :iterm2] do
    Native.session_set_image_protocol(ref, protocol)
  end

  @doc """
  Sets the client terminal's cell pixel dimensions for image rendering.

  Used together with `set_image_protocol/2` over byte-stream transports
  (SSH, Distributed) where we can't probe the client. With both set,
  Kitty / Sixel / iTerm2 encoders get the correct scaling math; without
  it, the render path falls back to ratatui-image's `(8, 16)` default
  which mis-scales on most modern terminals (Kitty/Ghostty default near
  `(10, 20)`).

  Pass `{0, 0}` to clear.

  ## Examples

      iex> session = ExRatatui.Session.new(20, 5)
      iex> ExRatatui.Session.set_image_font_size(session, {10, 20})
      :ok
  """
  @spec set_image_font_size(t(), {non_neg_integer(), non_neg_integer()}) :: :ok
  def set_image_font_size(%__MODULE__{ref: ref}, {w, h})
      when is_integer(w) and w >= 0 and is_integer(h) and h >= 0 do
    Native.session_set_image_font_size(ref, {w, h})
  end
end
