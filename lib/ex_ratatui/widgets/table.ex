defmodule ExRatatui.Widgets.Table do
  @moduledoc """
  A table widget with headers, rows, and optional selection.

  ## Fields

    * `:rows` - list of rows. Each row is a list of cells, and each cell
      accepts any `ExRatatui.Text`-coercible line-like value: a `String.t()`,
      a `%ExRatatui.Text.Span{}`, a `%ExRatatui.Text.Line{}`, or a list of
      spans. Cells are single-line — strings with embedded newlines raise.
    * `:header` - optional list of header cells (same shape as row cells)
    * `:widths` - list of constraint tuples for column widths
      (e.g., `[{:length, 10}, {:percentage, 50}, {:min, 5}]`)
    * `:style` - `%ExRatatui.Style{}` for the table
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container
    * `:highlight_style` - `%ExRatatui.Style{}` for the selected row
    * `:highlight_symbol` - string prefix for the selected row
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
        widths: [length: 15, length: 10],
        style: %ExRatatui.Style{},
        block: nil,
        highlight_style: %ExRatatui.Style{},
        highlight_symbol: nil,
        selected: nil,
        column_spacing: 1
      }
  """

  @type cell ::
          String.t()
          | ExRatatui.Text.Span.t()
          | ExRatatui.Text.Line.t()
          | [ExRatatui.Text.Span.t()]

  @type t :: %__MODULE__{
          rows: [[cell()]],
          header: [cell()] | nil,
          widths: [ExRatatui.Layout.constraint()],
          style: ExRatatui.Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil,
          highlight_style: ExRatatui.Style.t(),
          highlight_symbol: String.t() | nil,
          selected: non_neg_integer() | nil,
          column_spacing: non_neg_integer()
        }

  defstruct rows: [],
            header: nil,
            widths: [],
            style: %ExRatatui.Style{},
            block: nil,
            highlight_style: %ExRatatui.Style{},
            highlight_symbol: nil,
            selected: nil,
            column_spacing: 1
end
