# Example: Layout — every Flex mode + Constraint::Fill + segment
# spacing rendered visually so the demo *shows* the layout instead of
# describing it.
#
# Top half: five rows, one per :flex mode. Each row paints three small
# 6-cell tiles at the positions ratatui's layout engine assigns under
# that mode. The label on the left names the mode.
#
# Bottom half: three growable panels with `{:fill, 1/2/3}` weights and
# a 2-cell `spacing:` gutter. The widths are proportional to the
# weights — third panel three times wider than the first.
#
# Press q or Esc to quit.
# Run with:  mix run examples/layout/flex.exs

alias ExRatatui.{Event, Layout, Style, Theme}
alias ExRatatui.Layout.Rect
alias ExRatatui.Widgets.{Block, Paragraph}
alias ExRatatui.Widgets.Block.Title

defmodule LayoutFlexDemo do
  use ExRatatui.App

  @flex_modes [:start, :center, :end, :space_between, :space_around]

  # Each tile is 6 cells wide; three of them per row.
  @tile_width 6
  @tile_count 3

  # Pleasant accent per tile so adjacent tiles stay visually distinct.
  @tile_colors [:cyan, :magenta, :yellow]

  @impl true
  def mount(_opts) do
    {:ok, %{theme: Theme.default()}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    # Layout: 1-line header, one 3-line row per :flex mode (plus a
    # 1-line gap between rows so the strips don't visually run
    # together), rest goes to the fill row, 1-line footer.
    flex_rows = length(@flex_modes)
    flex_row_gap = 1
    flex_section_height = flex_rows * 3 + (flex_rows - 1) * flex_row_gap

    # `margin: 1` insets the whole screen by one cell before splitting,
    # leaving a one-cell breathing border around the entire demo.
    [header, flex_section, fill_section, footer] =
      Layout.split(
        area,
        :vertical,
        [
          {:length, 1},
          {:length, flex_section_height},
          {:min, 4},
          {:length, 1}
        ],
        margin: 1
      )

    [
      {header_widget(state), header}
      | flex_section_widgets(state, flex_section) ++
          fill_section_widgets(state, fill_section) ++
          [{footer_widget(state), footer}]
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["q", "esc"] do
    {:stop, state}
  end

  def handle_event(_, state), do: {:noreply, state}

  # --- header / footer -------------------------------------------------

  defp header_widget(state) do
    %Paragraph{
      text: " ExRatatui.Layout.split/4 — flex modes + Constraint::Fill + spacing ",
      alignment: :center,
      style: %Style{fg: state.theme.surface, bg: state.theme.accent, modifiers: [:bold]}
    }
  end

  defp footer_widget(state) do
    %Paragraph{
      text: " q or Esc to quit ",
      alignment: :right,
      style: %Style{fg: :black, bg: state.theme.warning, modifiers: [:bold]}
    }
  end

  # --- flex section ----------------------------------------------------

  defp flex_section_widgets(state, area) do
    # One row per flex mode, each row 3 cells tall, separated by a
    # 1-cell vertical gap (spacing: 1) so adjacent rows don't visually
    # touch.
    row_rects =
      Layout.split(
        area,
        :vertical,
        Enum.map(@flex_modes, fn _ -> {:length, 3} end),
        spacing: 1
      )

    Enum.zip(@flex_modes, row_rects)
    |> Enum.flat_map(fn {mode, row_rect} -> flex_row_widgets(state, mode, row_rect) end)
  end

  defp flex_row_widgets(state, mode, row_rect) do
    # Reserve 16 cells on the left for the mode label, the rest for
    # the flex-positioned tiles.
    [label_rect, tiles_rect] =
      Layout.split(row_rect, :horizontal, [{:length, 16}, {:min, 0}])

    # Three 6-cell tiles inside the tiles_rect. The flex mode controls
    # where they land within that area; the returned rects already
    # carry the absolute x coordinates we need for render. `spacing: 2`
    # keeps adjacent tiles visually distinct in :start / :center / :end
    # (where they'd otherwise touch with no gap between the colored
    # blocks, since each tile is fully filled from edge to edge).
    tile_rects =
      Layout.split(
        tiles_rect,
        :horizontal,
        Enum.map(1..@tile_count, fn _ -> {:length, @tile_width} end),
        flex: mode,
        spacing: 2
      )

    tile_widgets =
      tile_rects
      |> Enum.zip(@tile_colors)
      |> Enum.map(fn {rect, color} -> {tile_widget(color), rect} end)

    [{label_widget(state, mode), label_rect} | tile_widgets]
  end

  defp label_widget(state, mode) do
    %Paragraph{
      text: " :#{mode}",
      style: %Style{fg: state.theme.accent, modifiers: [:bold]}
    }
  end

  defp tile_widget(color) do
    %Block{
      borders: [:all],
      border_type: :plain,
      border_style: %Style{fg: color},
      style: %Style{bg: color}
    }
  end

  # --- fill section ----------------------------------------------------

  defp fill_section_widgets(state, area) do
    [title_rect, panels_rect] =
      Layout.split(area, :vertical, [{:length, 1}, {:min, 0}])

    [a, b, c] =
      Layout.split(panels_rect, :horizontal, [{:fill, 1}, {:fill, 2}, {:fill, 3}], spacing: 2)

    [
      {fill_title_widget(state), title_rect},
      {fill_panel(state, "{:fill, 1}", "1 share of leftover space", :primary), a},
      {fill_panel(state, "{:fill, 2}", "2 shares", :accent), b},
      {fill_panel(state, "{:fill, 3}", "3 shares — widest panel", :success), c}
    ]
  end

  defp fill_title_widget(state) do
    %Paragraph{
      text: " {:fill, weight} + spacing: 2 ",
      style: %Style{fg: state.theme.accent, modifiers: [:bold]}
    }
  end

  defp fill_panel(state, title, body, accent_slot) do
    accent = Map.fetch!(state.theme, accent_slot)

    %Paragraph{
      text: body,
      style: %Style{fg: state.theme.text},
      wrap: true,
      block: %Block{
        title: title,
        title_style: %Style{fg: accent, modifiers: [:bold]},
        titles: [%Title{content: "▶", alignment: :right, style: %Style{fg: accent}}],
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: accent}
      }
    }
  end
end

{:ok, pid} = LayoutFlexDemo.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
