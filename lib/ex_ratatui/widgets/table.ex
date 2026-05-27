defmodule ExRatatui.Widgets.Table do
  @moduledoc """
  A table widget with headers, rows, footer, and optional selection.

  ## Fields

    * `:rows` - list of rows. Each row is a list of cells, and each cell
      accepts any `ExRatatui.Text`-coercible line-like value: a `String.t()`,
      a `%ExRatatui.Text.Span{}`, a `%ExRatatui.Text.Line{}`, or a list of
      spans. Cells are single-line — strings with embedded newlines raise.
    * `:header` - optional list of header cells (same shape as row cells)
    * `:footer` - optional list of footer cells (same shape as row cells).
      Renders at the bottom of the table area.
    * `:widths` - list of constraint tuples for column widths
      (e.g., `[{:length, 10}, {:percentage, 50}, {:min, 5}]`)
    * `:style` - `%ExRatatui.Style{}` for the table
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container
    * `:highlight_style` - `%ExRatatui.Style{}` for the selected row (row-level highlight)
    * `:column_highlight_style` - `%ExRatatui.Style{}` for the selected
      column. `nil` means no column highlight.
    * `:cell_highlight_style` - `%ExRatatui.Style{}` for the selected
      cell (intersection of selected row + selected column). `nil` means
      no per-cell highlight.
    * `:header_style` - `%ExRatatui.Style{}` applied to the header row.
      `nil` falls back to the table's `:style`.
    * `:footer_style` - `%ExRatatui.Style{}` applied to the footer row.
      `nil` falls back to the table's `:style`.
    * `:highlight_symbol` - string prefix for the selected row
    * `:highlight_spacing` - when to reserve the highlight symbol
      column. One of `:always`, `:when_selected` (default — matches
      ratatui), or `:never`.
    * `:selected` - zero-based index of the selected row, or `nil`. Must be in
      `0..length(rows) - 1`; any other value raises `ArgumentError` at render time.
    * `:column_spacing` - spacing between columns (default: 1)

  ## Examples

      iex> %ExRatatui.Widgets.Table{
      ...>   rows: [["Alice", "30"], ["Bob", "25"]],
      ...>   header: ["Name", "Age"],
      ...>   widths: [{:length, 15}, {:length, 10}]
      ...> }
      %ExRatatui.Widgets.Table{
        rows: [["Alice", "30"], ["Bob", "25"]],
        header: ["Name", "Age"],
        footer: nil,
        widths: [length: 15, length: 10],
        style: %ExRatatui.Style{},
        block: nil,
        highlight_style: %ExRatatui.Style{},
        column_highlight_style: nil,
        cell_highlight_style: nil,
        header_style: nil,
        footer_style: nil,
        highlight_symbol: nil,
        highlight_spacing: :when_selected,
        selected: nil,
        column_spacing: 1
      }
  """

  @type cell ::
          String.t()
          | ExRatatui.Text.Span.t()
          | ExRatatui.Text.Line.t()
          | [ExRatatui.Text.Span.t()]

  @type highlight_spacing :: :always | :when_selected | :never

  @type t :: %__MODULE__{
          rows: [[cell()]],
          header: [cell()] | nil,
          footer: [cell()] | nil,
          widths: [ExRatatui.Layout.constraint()],
          style: ExRatatui.Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil,
          highlight_style: ExRatatui.Style.t(),
          column_highlight_style: ExRatatui.Style.t() | nil,
          cell_highlight_style: ExRatatui.Style.t() | nil,
          header_style: ExRatatui.Style.t() | nil,
          footer_style: ExRatatui.Style.t() | nil,
          highlight_symbol: String.t() | nil,
          highlight_spacing: highlight_spacing(),
          selected: non_neg_integer() | nil,
          column_spacing: non_neg_integer()
        }

  defstruct rows: [],
            header: nil,
            footer: nil,
            widths: [],
            style: %ExRatatui.Style{},
            block: nil,
            highlight_style: %ExRatatui.Style{},
            column_highlight_style: nil,
            cell_highlight_style: nil,
            header_style: nil,
            footer_style: nil,
            highlight_symbol: nil,
            highlight_spacing: :when_selected,
            selected: nil,
            column_spacing: 1
end
