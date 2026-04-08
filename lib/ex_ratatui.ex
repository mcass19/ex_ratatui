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

  ## Widgets

  See `ExRatatui.Widgets.Paragraph`, `ExRatatui.Widgets.Block`,
  `ExRatatui.Widgets.List`, `ExRatatui.Widgets.Table`,
  `ExRatatui.Widgets.Gauge`, `ExRatatui.Widgets.LineGauge`,
  `ExRatatui.Widgets.Tabs`, `ExRatatui.Widgets.Scrollbar`,
  `ExRatatui.Widgets.Checkbox`, `ExRatatui.Widgets.TextInput`,
  `ExRatatui.Widgets.Clear`, `ExRatatui.Widgets.Markdown`,
  `ExRatatui.Widgets.Textarea`, `ExRatatui.Widgets.Throbber`,
  `ExRatatui.Widgets.Popup`, and `ExRatatui.Widgets.WidgetList`.

  ## Testing

  Use `init_test_terminal/2` and `get_buffer_content/1` for headless
  rendering verification in CI — no TTY required.
  """

  require Logger

  alias ExRatatui.Event
  alias ExRatatui.Native
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style

  alias ExRatatui.Widgets.{
    Block,
    Checkbox,
    Clear,
    Gauge,
    LineGauge,
    List,
    Markdown,
    Paragraph,
    Scrollbar,
    Table,
    Tabs,
    Popup,
    Textarea,
    TextInput,
    Throbber,
    WidgetList
  }

  @type terminal_ref :: reference()

  @type widget ::
          Paragraph.t()
          | Block.t()
          | Checkbox.t()
          | Clear.t()
          | List.t()
          | Table.t()
          | Gauge.t()
          | LineGauge.t()
          | Tabs.t()
          | Scrollbar.t()
          | Markdown.t()
          | Popup.t()
          | Textarea.t()
          | TextInput.t()
          | Throbber.t()
          | WidgetList.t()

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
    try do
      fun.(terminal_ref)
    after
      safe_restore_terminal(terminal_ref)
    end
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
    commands = Enum.map(widgets, &encode_command/1)
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
  def encode_command({widget, %Rect{} = rect}) do
    {encode_widget(widget), encode_rect(rect)}
  end

  defp encode_widget(%Paragraph{} = p) do
    %{
      "type" => "paragraph",
      "text" => p.text,
      "style" => encode_style(p.style),
      "alignment" => Atom.to_string(p.alignment),
      "wrap" => p.wrap,
      "scroll_y" => elem(p.scroll, 0),
      "scroll_x" => elem(p.scroll, 1)
    }
    |> maybe_put_block(p.block)
  end

  defp encode_widget(%Block{} = b) do
    encode_block(b)
    |> Map.put("type", "block")
  end

  defp encode_widget(%List{} = l) do
    %{
      "type" => "list",
      "items" => l.items,
      "style" => encode_style(l.style),
      "highlight_style" => encode_style(l.highlight_style)
    }
    |> maybe_put("highlight_symbol", l.highlight_symbol)
    |> maybe_put("selected", l.selected)
    |> maybe_put_block(l.block)
  end

  defp encode_widget(%Table{} = t) do
    %{
      "type" => "table",
      "rows" => t.rows,
      "widths" => Enum.map(t.widths, &encode_constraint/1),
      "style" => encode_style(t.style),
      "highlight_style" => encode_style(t.highlight_style),
      "column_spacing" => t.column_spacing
    }
    |> maybe_put("header", t.header)
    |> maybe_put("highlight_symbol", t.highlight_symbol)
    |> maybe_put("selected", t.selected)
    |> maybe_put_block(t.block)
  end

  defp encode_widget(%Clear{}) do
    %{"type" => "clear"}
  end

  defp encode_widget(%Gauge{} = g) do
    %{
      "type" => "gauge",
      "ratio" => g.ratio * 1.0,
      "style" => encode_style(g.style),
      "gauge_style" => encode_style(g.gauge_style)
    }
    |> maybe_put("label", g.label)
    |> maybe_put_block(g.block)
  end

  defp encode_widget(%LineGauge{} = lg) do
    %{
      "type" => "line_gauge",
      "ratio" => lg.ratio * 1.0,
      "style" => encode_style(lg.style),
      "filled_style" => encode_style(lg.filled_style),
      "unfilled_style" => encode_style(lg.unfilled_style)
    }
    |> maybe_put("label", lg.label)
    |> maybe_put_block(lg.block)
  end

  defp encode_widget(%Tabs{} = t) do
    %{
      "type" => "tabs",
      "titles" => t.titles,
      "style" => encode_style(t.style),
      "highlight_style" => encode_style(t.highlight_style),
      "padding_left" => elem(t.padding, 0),
      "padding_right" => elem(t.padding, 1)
    }
    |> maybe_put("selected", t.selected)
    |> maybe_put("divider", t.divider)
    |> maybe_put_block(t.block)
  end

  defp encode_widget(%Scrollbar{} = s) do
    %{
      "type" => "scrollbar",
      "orientation" => Atom.to_string(s.orientation),
      "content_length" => s.content_length,
      "position" => s.position,
      "thumb_style" => encode_style(s.thumb_style),
      "track_style" => encode_style(s.track_style)
    }
    |> maybe_put("viewport_content_length", s.viewport_content_length)
    |> maybe_put("thumb_symbol", s.thumb_symbol)
    |> maybe_put("track_symbol", s.track_symbol)
    |> maybe_put("begin_symbol", s.begin_symbol)
    |> maybe_put("end_symbol", s.end_symbol)
  end

  defp encode_widget(%Checkbox{} = c) do
    %{
      "type" => "checkbox",
      "label" => c.label,
      "checked" => c.checked,
      "style" => encode_style(c.style),
      "checked_style" => encode_style(c.checked_style)
    }
    |> maybe_put("checked_symbol", c.checked_symbol)
    |> maybe_put("unchecked_symbol", c.unchecked_symbol)
    |> maybe_put_block(c.block)
  end

  defp encode_widget(%TextInput{} = t) do
    %{
      "type" => "text_input",
      "state" => t.state,
      "style" => encode_style(t.style),
      "cursor_style" => encode_style(t.cursor_style),
      "placeholder_style" => encode_style(t.placeholder_style)
    }
    |> maybe_put("placeholder", t.placeholder)
    |> maybe_put_block(t.block)
  end

  defp encode_widget(%Markdown{} = m) do
    %{
      "type" => "markdown",
      "content" => m.content,
      "style" => encode_style(m.style),
      "wrap" => m.wrap,
      "scroll_y" => elem(m.scroll, 0),
      "scroll_x" => elem(m.scroll, 1)
    }
    |> maybe_put_block(m.block)
  end

  defp encode_widget(%Textarea{} = t) do
    %{
      "type" => "textarea",
      "state" => t.state,
      "style" => encode_style(t.style),
      "cursor_style" => encode_style(t.cursor_style),
      "cursor_line_style" => encode_style(t.cursor_line_style),
      "placeholder_style" => encode_style(t.placeholder_style)
    }
    |> maybe_put("placeholder", t.placeholder)
    |> maybe_put_style("line_number_style", t.line_number_style)
    |> maybe_put_block(t.block)
  end

  defp encode_widget(%Popup{content: nil}) do
    raise ArgumentError, "Popup :content is required — pass a widget struct"
  end

  defp encode_widget(%Popup{} = p) do
    base = %{
      "type" => "popup",
      "content" => encode_widget(p.content),
      "percent_width" => p.percent_width,
      "percent_height" => p.percent_height
    }

    base
    |> maybe_put("fixed_width", p.fixed_width)
    |> maybe_put("fixed_height", p.fixed_height)
    |> maybe_put_block(p.block)
  end

  defp encode_widget(%WidgetList{} = wl) do
    items =
      Enum.map(wl.items, fn {widget, height} ->
        {encode_widget(widget), height}
      end)

    %{
      "type" => "widget_list",
      "items" => items,
      "style" => encode_style(wl.style),
      "highlight_style" => encode_style(wl.highlight_style),
      "scroll_offset" => wl.scroll_offset
    }
    |> maybe_put("selected", wl.selected)
    |> maybe_put_block(wl.block)
  end

  defp encode_widget(%Throbber{} = t) do
    %{
      "type" => "throbber",
      "label" => t.label,
      "style" => encode_style(t.style),
      "throbber_style" => encode_style(t.throbber_style),
      "throbber_set" => Atom.to_string(t.throbber_set),
      "step" => t.step
    }
    |> maybe_put_block(t.block)
  end

  defp encode_block(%Block{} = b) do
    %{
      "borders" => Enum.map(b.borders, &Atom.to_string/1),
      "border_style" => encode_style(b.border_style),
      "border_type" => Atom.to_string(b.border_type),
      "style" => encode_style(b.style),
      "padding_left" => elem(b.padding, 0),
      "padding_right" => elem(b.padding, 1),
      "padding_top" => elem(b.padding, 2),
      "padding_bottom" => elem(b.padding, 3)
    }
    |> maybe_put("title", b.title)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_style(map, _key, nil), do: map
  defp maybe_put_style(map, key, %Style{} = s), do: Map.put(map, key, encode_style(s))

  defp maybe_put_block(map, nil), do: map
  defp maybe_put_block(map, %Block{} = b), do: Map.put(map, "block", encode_block(b))

  defp encode_constraint(constraint), do: ExRatatui.Layout.encode_constraint(constraint)

  defp encode_style(%Style{} = s) do
    style = %{"modifiers" => Enum.map(s.modifiers, &Atom.to_string/1)}
    style = if s.fg, do: Map.put(style, "fg", encode_color(s.fg)), else: style
    if s.bg, do: Map.put(style, "bg", encode_color(s.bg)), else: style
  end

  defp encode_color(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp encode_color({:rgb, r, g, b}), do: %{"type" => "rgb", "r" => r, "g" => g, "b" => b}
  defp encode_color({:indexed, i}), do: %{"type" => "indexed", "value" => i}

  defp encode_rect(%Rect{} = r) do
    %{"x" => r.x, "y" => r.y, "width" => r.width, "height" => r.height}
  end
end
