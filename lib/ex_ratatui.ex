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
  and `ExRatatui.Widgets.Clear`.

  ## Testing

  Use `init_test_terminal/2` and `get_buffer_content/1` for headless
  rendering verification in CI — no TTY required.
  """

  alias ExRatatui.Native
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style

  alias ExRatatui.Widgets.{
    Block,
    Clear,
    Gauge,
    LineGauge,
    List,
    Paragraph,
    Scrollbar,
    Table,
    Tabs
  }

  @type terminal_ref :: reference()

  @type widget ::
          Paragraph.t()
          | Block.t()
          | Clear.t()
          | List.t()
          | Table.t()
          | Gauge.t()
          | LineGauge.t()
          | Tabs.t()
          | Scrollbar.t()

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
    case Native.init_terminal() do
      {:error, reason} ->
        {:error, reason}

      terminal_ref ->
        try do
          fun.(terminal_ref)
        after
          try do
            Native.restore_terminal(terminal_ref)
          rescue
            e ->
              require Logger
              Logger.warning("Failed to restore terminal: #{Exception.message(e)}")
          end
        end
    end
  end

  @doc """
  Draws a list of `{widget, rect}` tuples to the terminal in a single frame.

  Returns `:ok` on success or `{:error, reason}` on failure.

      ExRatatui.draw(terminal, [
        {%ExRatatui.Widgets.Paragraph{text: "Hello!"}, rect}
      ])
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
    alias ExRatatui.Event

    case Native.poll_event(timeout_ms) do
      nil ->
        nil

      {:key, code, modifiers, kind} ->
        %Event.Key{code: code, modifiers: modifiers, kind: kind}

      {:mouse, kind, button, x, y, modifiers} ->
        %Event.Mouse{kind: kind, button: button, x: x, y: y, modifiers: modifiers}

      {:resize, width, height} ->
        %Event.Resize{width: width, height: height}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Returns the current terminal size as `{width, height}`.

  Returns `{:error, reason}` if the terminal size cannot be determined.
  """
  @spec terminal_size() :: {non_neg_integer(), non_neg_integer()} | {:error, term()}
  def terminal_size do
    case Native.terminal_size() do
      {w, h} when is_integer(w) and is_integer(h) -> {w, h}
      {:error, _} = err -> err
    end
  end

  @doc """
  Initializes a headless test terminal with the given dimensions.

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
  """
  @spec get_buffer_content(terminal_ref()) :: String.t() | {:error, term()}
  def get_buffer_content(terminal_ref) do
    Native.get_buffer_content(terminal_ref)
  end

  # -- Encoding: Elixir structs -> string-keyed maps for NIF --

  defp encode_command({widget, %Rect{} = rect}) do
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
