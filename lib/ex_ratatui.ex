defmodule ExRatatui do
  @moduledoc """
  Elixir bindings for the Rust [ratatui](https://ratatui.rs) terminal UI library.

  This module provides the core API for building terminal UIs: initializing
  the terminal, drawing widgets, and polling for events — all via Rust NIFs
  that run on the BEAM's DirtyIo scheduler.

  ## Quick start

      ExRatatui.run(fn terminal ->
        {w, h} = ExRatatui.terminal_size()
        paragraph = %ExRatatui.Widgets.Paragraph{text: "Hello!"}
        rect = %ExRatatui.Layout.Rect{x: 0, y: 0, width: w, height: h}

        ExRatatui.draw(terminal, [{paragraph, rect}])
        ExRatatui.poll_event(60_000)
      end)

  ## Core functions

    * `run/1` — initialize the terminal, run a function, restore on exit
    * `draw/2` — render a list of `{widget, rect}` tuples in a single frame
    * `poll_event/1` — non-blocking event polling (keyboard, mouse, resize)
    * `terminal_size/0` — current terminal dimensions

  ## OTP apps

  For supervised TUI applications, see `ExRatatui.App` — a behaviour with
  LiveView-inspired callbacks (`mount/1`, `render/2`, `handle_event/2`).

  ## Running over SSH

  To serve a TUI to remote clients without a local terminal, see
  `ExRatatui.SSH.Daemon` and the [SSH transport guide](guides/ssh_transport.md).

  ## Widgets

  See `ExRatatui.Widgets.Paragraph`, `ExRatatui.Widgets.Block`,
  `ExRatatui.Widgets.List`, `ExRatatui.Widgets.Table`,
  `ExRatatui.Widgets.Gauge`, `ExRatatui.Widgets.LineGauge`,
  `ExRatatui.Widgets.BarChart`, `ExRatatui.Widgets.Sparkline`,
  `ExRatatui.Widgets.Tabs`,
  `ExRatatui.Widgets.Scrollbar`, `ExRatatui.Widgets.Checkbox`,
  `ExRatatui.Widgets.TextInput`, `ExRatatui.Widgets.Clear`,
  `ExRatatui.Widgets.Markdown`, `ExRatatui.Widgets.Textarea`,
  `ExRatatui.Widgets.Throbber`, `ExRatatui.Widgets.Popup`,
  and `ExRatatui.Widgets.WidgetList`.

  ## Testing

  Use `init_test_terminal/2` and `get_buffer_content/1` for headless
  rendering verification in CI — no TTY required.
  """

  require Logger

  alias ExRatatui.Event
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native

  alias ExRatatui.Widgets.{
    BarChart,
    Block,
    Checkbox,
    Clear,
    Gauge,
    LineGauge,
    List,
    Markdown,
    Paragraph,
    Popup,
    Scrollbar,
    Sparkline,
    Table,
    Tabs,
    Textarea,
    TextInput,
    Throbber,
    WidgetList
  }

  @type terminal_ref :: reference()

  @typedoc """
  Built-in widget structs the library renders natively.

  `draw/2` also accepts user-defined structs that implement the
  `ExRatatui.Widget` protocol — see `t:widget/0`.
  """
  @type primitive_widget ::
          Paragraph.t()
          | Block.t()
          | Checkbox.t()
          | Clear.t()
          | List.t()
          | Table.t()
          | Gauge.t()
          | LineGauge.t()
          | BarChart.t()
          | Sparkline.t()
          | Tabs.t()
          | Scrollbar.t()
          | Markdown.t()
          | Popup.t()
          | Textarea.t()
          | TextInput.t()
          | Throbber.t()
          | WidgetList.t()

  @typedoc """
  Anything `draw/2` accepts: a primitive widget struct or any struct
  implementing `ExRatatui.Widget`.
  """
  @type widget :: primitive_widget() | struct()

  @doc """
  Runs a TUI application.

  Initializes the terminal, calls `fun` with the terminal reference,
  and ensures terminal cleanup on exit.

      ExRatatui.run(fn terminal ->
        # your TUI loop here
      end)
  """
  @spec run((terminal_ref() -> term())) :: term() | {:error, term()}
  def run(fun) when is_function(fun, 1) do
    Native.init_terminal() |> do_run(fun)
  end

  @doc false
  def do_run({:error, reason}, _fun), do: {:error, reason}
  def do_run(terminal_ref, fun), do: execute_with_terminal(terminal_ref, fun)

  @doc false
  def execute_with_terminal(terminal_ref, fun) do
    fun.(terminal_ref)
  after
    safe_restore_terminal(terminal_ref)
  end

  @doc false
  def safe_restore_terminal(terminal_ref) do
    Native.restore_terminal(terminal_ref)
  rescue
    e ->
      Logger.warning("Failed to restore terminal: #{Exception.message(e)}")
  end

  @doc """
  Draws a list of `{widget, rect}` tuples to the terminal in a single frame.

  Each tuple pairs a widget struct (e.g. `%Paragraph{}`, `%Table{}`) with a
  `%Rect{}` that defines where to render it. Returns `:ok` on success or
  `{:error, reason}` on failure.

  ## Examples

      iex> terminal = ExRatatui.init_test_terminal(40, 10)
      iex> paragraph = %ExRatatui.Widgets.Paragraph{text: "Hello!"}
      iex> rect = %ExRatatui.Layout.Rect{x: 0, y: 0, width: 40, height: 10}
      iex> ExRatatui.draw(terminal, [{paragraph, rect}])
      :ok
  """
  @spec draw(terminal_ref(), [{widget(), Rect.t()}]) :: :ok | {:error, term()}
  def draw(terminal_ref, widgets) when is_list(widgets) do
    commands = ExRatatui.Bridge.encode_commands!(widgets)
    Native.draw_frame(terminal_ref, commands)
  end

  @doc """
  Polls for terminal events with a timeout (default 250ms).

  Returns an `Event.Key`, `Event.Mouse`, `Event.Resize` struct, `nil`
  if no event within the timeout, or `{:error, reason}` on failure.
  """
  @spec poll_event(non_neg_integer()) ::
          ExRatatui.Event.t() | nil | {:error, term()}
  def poll_event(timeout_ms \\ 250) do
    timeout_ms |> Native.poll_event() |> decode_event()
  end

  @doc false
  def decode_event(nil), do: nil

  def decode_event({:key, code, modifiers, kind}),
    do: %Event.Key{code: code, modifiers: modifiers, kind: kind}

  def decode_event({:mouse, kind, button, x, y, modifiers}),
    do: %Event.Mouse{kind: kind, button: button, x: x, y: y, modifiers: modifiers}

  def decode_event({:resize, width, height}),
    do: %Event.Resize{width: width, height: height}

  def decode_event({:error, _} = err), do: err

  @doc """
  Returns the current terminal size as `{width, height}`.

  Returns `{:error, reason}` if the terminal size cannot be determined.
  """
  @spec terminal_size() :: {non_neg_integer(), non_neg_integer()} | {:error, term()}
  def terminal_size do
    Native.terminal_size() |> validate_terminal_size()
  end

  @doc false
  def validate_terminal_size({w, h}) when is_integer(w) and is_integer(h), do: {w, h}
  def validate_terminal_size({:error, _} = err), do: err

  @doc """
  Initializes a headless test terminal with the given dimensions.

  Takes `width` (columns) and `height` (rows) for the virtual terminal.
  Uses ratatui's TestBackend — no real terminal needed. Useful for testing
  rendering output without a TTY. Returns a terminal reference.

  ## Examples

      iex> terminal = ExRatatui.init_test_terminal(40, 10)
      iex> is_reference(terminal)
      true

      iex> terminal = ExRatatui.init_test_terminal(40, 10)
      iex> alias ExRatatui.Widgets.Paragraph
      iex> alias ExRatatui.Layout.Rect
      iex> :ok = ExRatatui.draw(terminal, [{%Paragraph{text: "Hello!"}, %Rect{x: 0, y: 0, width: 40, height: 10}}])
      iex> ExRatatui.get_buffer_content(terminal) =~ "Hello!"
      true
  """
  @spec init_test_terminal(non_neg_integer(), non_neg_integer()) ::
          terminal_ref() | {:error, term()}
  def init_test_terminal(width, height) do
    Native.init_test_terminal(width, height)
  end

  @doc """
  Returns the test terminal's buffer contents as a string.

  Each line is trimmed of trailing whitespace and joined with newlines.
  Only works with a test terminal reference from `init_test_terminal/2`.

  ## Examples

      iex> terminal = ExRatatui.init_test_terminal(20, 3)
      iex> paragraph = %ExRatatui.Widgets.Paragraph{text: "Hi there"}
      iex> rect = %ExRatatui.Layout.Rect{x: 0, y: 0, width: 20, height: 3}
      iex> ExRatatui.draw(terminal, [{paragraph, rect}])
      iex> ExRatatui.get_buffer_content(terminal) =~ "Hi there"
      true
  """
  @spec get_buffer_content(terminal_ref()) :: String.t() | {:error, term()}
  def get_buffer_content(terminal_ref) do
    Native.get_buffer_content(terminal_ref)
  end

  # -- TextInput (stateful widget) --

  @doc """
  Creates a new TextInput state.

  Returns a reference to the Rust-side state (ResourceArc). Pass this
  reference as the `:state` field of `%ExRatatui.Widgets.TextInput{}`.

  ## Examples

      iex> state = ExRatatui.text_input_new()
      iex> is_reference(state)
      true
  """
  @spec text_input_new() :: reference()
  def text_input_new, do: Native.text_input_new()

  @doc """
  Forwards a key event to the TextInput state.

  Pass the `code` field from an `ExRatatui.Event.Key` struct. Supports
  printable characters, `"backspace"`, `"delete"`, `"left"`, `"right"`,
  `"home"`, and `"end"`.

  ## Examples

      iex> state = ExRatatui.text_input_new()
      iex> ExRatatui.text_input_handle_key(state, "h")
      :ok
      iex> ExRatatui.text_input_handle_key(state, "i")
      :ok
      iex> ExRatatui.text_input_get_value(state)
      "hi"
  """
  @spec text_input_handle_key(reference(), String.t()) :: :ok
  def text_input_handle_key(state_ref, key_code),
    do: Native.text_input_handle_key(state_ref, key_code)

  @doc """
  Returns the current text value from the TextInput state.

  ## Examples

      iex> state = ExRatatui.text_input_new()
      iex> ExRatatui.text_input_get_value(state)
      ""
  """
  @spec text_input_get_value(reference()) :: String.t()
  def text_input_get_value(state_ref), do: Native.text_input_get_value(state_ref)

  @doc """
  Sets the text value on the TextInput state.

  The cursor is moved to the end of the new value.

  ## Examples

      iex> state = ExRatatui.text_input_new()
      iex> ExRatatui.text_input_set_value(state, "hello")
      :ok
      iex> ExRatatui.text_input_get_value(state)
      "hello"
  """
  @spec text_input_set_value(reference(), String.t()) :: :ok
  def text_input_set_value(state_ref, value),
    do: Native.text_input_set_value(state_ref, value)

  @doc """
  Returns the current cursor position from the TextInput state.

  ## Examples

      iex> state = ExRatatui.text_input_new()
      iex> ExRatatui.text_input_cursor(state)
      0
      iex> ExRatatui.text_input_handle_key(state, "a")
      :ok
      iex> ExRatatui.text_input_cursor(state)
      1
  """
  @spec text_input_cursor(reference()) :: non_neg_integer()
  def text_input_cursor(state_ref), do: Native.text_input_cursor(state_ref)

  # -- Textarea (stateful multiline widget) --

  @doc """
  Creates a new Textarea state.

  Returns a reference to the Rust-side state (ResourceArc). Pass this
  reference as the `:state` field of `%ExRatatui.Widgets.Textarea{}`.

  ## Examples

      iex> state = ExRatatui.textarea_new()
      iex> is_reference(state)
      true
  """
  @spec textarea_new() :: reference()
  def textarea_new, do: Native.textarea_new()

  @doc """
  Forwards a key event with modifiers to the Textarea state.

  `modifiers` is a list of active modifier strings (e.g. `["ctrl"]`),
  defaults to `[]`. The textarea supports Emacs-style shortcuts
  (Ctrl+Z undo, Ctrl+Y redo, etc.).

  ## Examples

      iex> state = ExRatatui.textarea_new()
      iex> ExRatatui.textarea_handle_key(state, "h", [])
      :ok
      iex> ExRatatui.textarea_handle_key(state, "i", [])
      :ok
      iex> ExRatatui.textarea_get_value(state)
      "hi"
  """
  @spec textarea_handle_key(reference(), String.t(), [String.t()]) :: :ok
  def textarea_handle_key(state_ref, key_code, modifiers \\ []),
    do: Native.textarea_handle_key(state_ref, key_code, modifiers)

  @doc """
  Returns the current text from the Textarea as a string (lines joined with \\n).

  ## Examples

      iex> state = ExRatatui.textarea_new()
      iex> ExRatatui.textarea_get_value(state)
      ""
  """
  @spec textarea_get_value(reference()) :: String.t()
  def textarea_get_value(state_ref), do: Native.textarea_get_value(state_ref)

  @doc """
  Sets the text value on the Textarea state.

  ## Examples

      iex> state = ExRatatui.textarea_new()
      iex> ExRatatui.textarea_set_value(state, "hello\\nworld")
      :ok
      iex> ExRatatui.textarea_get_value(state)
      "hello\\nworld"
  """
  @spec textarea_set_value(reference(), String.t()) :: :ok
  def textarea_set_value(state_ref, value),
    do: Native.textarea_set_value(state_ref, value)

  @doc """
  Returns the cursor position as `{row, col}` from the Textarea state.

  ## Examples

      iex> state = ExRatatui.textarea_new()
      iex> ExRatatui.textarea_cursor(state)
      {0, 0}
  """
  @spec textarea_cursor(reference()) :: {non_neg_integer(), non_neg_integer()}
  def textarea_cursor(state_ref), do: Native.textarea_cursor(state_ref)

  @doc """
  Returns the number of lines in the Textarea state.

  ## Examples

      iex> state = ExRatatui.textarea_new()
      iex> ExRatatui.textarea_line_count(state)
      1
  """
  @spec textarea_line_count(reference()) :: non_neg_integer()
  def textarea_line_count(state_ref), do: Native.textarea_line_count(state_ref)

  # -- Encoding: Elixir structs -> string-keyed maps for NIF --

  @doc false
  # Internal: shared by `ExRatatui.draw/2` (local transport via
  # `draw_frame`) and `ExRatatui.Session.draw/2` (per-connection
  # transport via `session_draw`). Both NIFs accept the same
  # `[{widget_map, rect_map}]` shape so we encode once here.
  def encode_command(command), do: ExRatatui.Bridge.encode_command(command)
end
