defmodule ExRatatui do
  @moduledoc """
  Ratatui TUI library bindings for Elixir.

  Provides terminal UI capabilities via Rust NIFs wrapping the ratatui crate.
  """

  alias ExRatatui.Native
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Gauge, List, Paragraph, Table}

  @type terminal_ref :: reference()

  @type widget ::
          Paragraph.t()
          | Block.t()
          | List.t()
          | Table.t()
          | Gauge.t()

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
          Native.restore_terminal(terminal_ref)
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

      terminal = ExRatatui.init_test_terminal(80, 24)
      ExRatatui.draw(terminal, [{widget, rect}])
      content = ExRatatui.get_buffer_content(terminal)
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
