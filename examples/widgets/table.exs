# Example: Data table — every new Table field on one screen.
#
# Exercises the six round-1 Table additions:
#   * :footer              (totals row at the bottom)
#   * :header_style        (bold accent on the header row)
#   * :footer_style        (dim accent on the totals row)
#   * :column_highlight_style  (highlights the selected column)
#   * :cell_highlight_style    (highlights the intersection of selected
#                                row + column with a popped color)
#   * :highlight_spacing :always
#                          (reserves the symbol column even when
#                            nothing is selected, so rows don't shift
#                            on selection toggle)
#
# Keys:
#   ↑ / ↓     move selected row
#   ← / →     move selected column
#   h         toggle header_style emphasis
#   Esc / q   quit
#
# Run with:  mix run examples/widgets/table.exs

alias ExRatatui.{Event, Layout, Style, Theme}
alias ExRatatui.Layout.Rect
alias ExRatatui.Text.{Line, Span}
alias ExRatatui.Widgets.{Block, Paragraph, Table}

defmodule DataTable do
  use ExRatatui.App

  @header ["Name", "Role", "Joined", "Capacity", "Open issues"]

  @rows [
    ["Alice", "Engineering", "2021-03", "85%", "4"],
    ["Bob", "Engineering", "2022-07", "70%", "11"],
    ["Carol", "Design", "2020-01", "100%", "0"],
    ["Dave", "Engineering", "2023-11", "60%", "6"],
    ["Eve", "Product", "2019-08", "90%", "2"],
    ["Frank", "Support", "2024-02", "50%", "18"]
  ]

  # Pre-compute footer numbers so the example doesn't recompute on
  # every render.
  @capacity_avg "75%"
  @open_total "41"
  @footer ["Σ #{length(@rows)} rows", "—", "—", @capacity_avg, @open_total]

  @columns length(@header)

  @impl true
  def mount(_opts) do
    {:ok,
     %{
       theme: Theme.default(),
       row: 0,
       col: 0,
       bold_header?: true
     }}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_rect, table_rect, footer_rect] =
      Layout.split(area, :vertical, [
        {:length, 1},
        {:min, 0},
        {:length, 1}
      ])

    [
      {title_widget(state), header_rect},
      {table_widget(state), table_rect},
      {footer_widget(state), footer_rect}
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["esc", "q"] do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, state) do
    {:noreply, %{state | row: max(state.row - 1, 0)}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, state) do
    {:noreply, %{state | row: min(state.row + 1, length(@rows) - 1)}}
  end

  def handle_event(%Event.Key{code: "left", kind: "press"}, state) do
    {:noreply, %{state | col: max(state.col - 1, 0)}}
  end

  def handle_event(%Event.Key{code: "right", kind: "press"}, state) do
    {:noreply, %{state | col: min(state.col + 1, @columns - 1)}}
  end

  def handle_event(%Event.Key{code: "h", kind: "press"}, state) do
    {:noreply, %{state | bold_header?: not state.bold_header?}}
  end

  def handle_event(_, state), do: {:noreply, state}

  # --- widgets ---------------------------------------------------------

  defp title_widget(state) do
    %Paragraph{
      text:
        " ExRatatui.Widgets.Table — footer + header/footer/column/cell styles + highlight_spacing ",
      alignment: :center,
      style: %Style{fg: state.theme.surface, bg: state.theme.accent, modifiers: [:bold]}
    }
  end

  # :column_highlight_style and :cell_highlight_style only fire when
  # the Table widget knows which column is selected — that's what
  # :selected_column is for. Pass the live col index through and the
  # widget paints the column tint + the cell pop on the intersection.
  defp table_widget(state) do
    %Table{
      header: @header,
      footer: @footer,
      rows: @rows,
      widths: [
        {:length, 8},
        {:length, 14},
        {:length, 9},
        {:length, 10},
        {:length, 13}
      ],
      selected: state.row,
      selected_column: state.col,
      column_spacing: 2,
      highlight_symbol: "› ",
      highlight_spacing: :always,
      highlight_style: %Style{
        fg: state.theme.surface,
        bg: state.theme.accent,
        modifiers: [:bold]
      },
      column_highlight_style: %Style{bg: state.theme.surface_alt},
      cell_highlight_style: %Style{
        fg: :black,
        bg: state.theme.warning,
        modifiers: [:bold]
      },
      header_style: header_style(state),
      footer_style: %Style{fg: state.theme.text_dim, modifiers: [:italic]},
      block: %Block{
        title: " team roster ",
        title_style: %Style{fg: state.theme.accent, modifiers: [:bold]},
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: state.theme.border}
      }
    }
  end

  defp header_style(state) do
    base = %Style{fg: state.theme.accent}
    if state.bold_header?, do: %{base | modifiers: [:bold]}, else: base
  end

  defp footer_widget(state) do
    %Paragraph{
      text:
        Line.new([
          chip(state, "↑/↓", :accent),
          Span.new(" row  "),
          chip(state, "←/→", :accent),
          Span.new(" col  "),
          chip(state, "h", :primary),
          Span.new(" toggle bold header  "),
          chip(state, "Esc/q", :danger),
          Span.new(" quit  "),
          Span.new("  selected: ", style: %Style{fg: state.theme.text_dim}),
          Span.new(
            "row #{state.row + 1}, col #{Enum.at(@header, state.col)}",
            style: %Style{fg: state.theme.accent, modifiers: [:bold]}
          )
        ])
    }
  end

  defp chip(state, label, slot) do
    Span.new(" #{label} ",
      style: %Style{fg: :black, bg: Map.fetch!(state.theme, slot), modifiers: [:bold]}
    )
  end
end

{:ok, pid} = DataTable.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
