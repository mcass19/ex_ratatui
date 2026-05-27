defmodule ExRatatui.Widgets.List do
  @moduledoc """
  A selectable list widget.

  ## Fields

    * `:items` - list of items to display. Each item accepts any
      `ExRatatui.Text`-coercible value: a `String.t()`, a `%ExRatatui.Text.Span{}`,
      a `%ExRatatui.Text.Line{}`, a `%ExRatatui.Text{}`, or a list of spans/lines.
    * `:style` - `%ExRatatui.Style{}` for non-selected items
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container
    * `:highlight_style` - `%ExRatatui.Style{}` for the selected item
    * `:highlight_symbol` - string prefix for the selected item (e.g., `">> "`)
    * `:selected` - zero-based index of the selected item, or `nil` for no
      selection. Must be in `0..length(items) - 1`; any other value raises
      `ArgumentError` at render time.

  ## Examples

      iex> %ExRatatui.Widgets.List{items: ["Alpha", "Beta", "Gamma"], selected: 0}
      %ExRatatui.Widgets.List{
        items: ["Alpha", "Beta", "Gamma"],
        style: %ExRatatui.Style{},
        block: nil,
        highlight_style: %ExRatatui.Style{},
        highlight_symbol: nil,
        selected: 0
      }
  """

  @type item ::
          String.t()
          | ExRatatui.Text.Span.t()
          | ExRatatui.Text.Line.t()
          | ExRatatui.Text.t()
          | [ExRatatui.Text.Span.t()]
          | [ExRatatui.Text.Line.t()]

  @type t :: %__MODULE__{
          items: [item()],
          style: ExRatatui.Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil,
          highlight_style: ExRatatui.Style.t(),
          highlight_symbol: String.t() | nil,
          selected: non_neg_integer() | nil
        }

  defstruct items: [],
            style: %ExRatatui.Style{},
            block: nil,
            highlight_style: %ExRatatui.Style{},
            highlight_symbol: nil,
            selected: nil
end
