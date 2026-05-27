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
    * `:direction` - `:top_to_bottom` (default) or `:bottom_to_top`. The
      latter paints the first item at the bottom of the area and grows
      upward — natural fit for chat logs, REPL history, and event streams
      where the newest entry pins to the bottom edge.
    * `:scroll_padding` - non-negative integer. The minimum number of
      rows kept visible above and below the selected item when the list
      auto-scrolls. `2` means the selection always has at least two rows
      of context on each side (or as many as the viewport allows).
      Defaults to `0`.
    * `:repeat_highlight_symbol` - `false` (default) renders the highlight
      symbol only on the first wrapped row of the selected item; `true`
      repeats it on every row. Useful for multi-line list items.

  ## Examples

      iex> %ExRatatui.Widgets.List{items: ["Alpha", "Beta", "Gamma"], selected: 0}
      %ExRatatui.Widgets.List{
        items: ["Alpha", "Beta", "Gamma"],
        style: %ExRatatui.Style{},
        block: nil,
        highlight_style: %ExRatatui.Style{},
        highlight_symbol: nil,
        selected: 0,
        direction: :top_to_bottom,
        scroll_padding: 0,
        repeat_highlight_symbol: false
      }
  """

  @type item ::
          String.t()
          | ExRatatui.Text.Span.t()
          | ExRatatui.Text.Line.t()
          | ExRatatui.Text.t()
          | [ExRatatui.Text.Span.t()]
          | [ExRatatui.Text.Line.t()]

  @type direction :: :top_to_bottom | :bottom_to_top

  @type t :: %__MODULE__{
          items: [item()],
          style: ExRatatui.Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil,
          highlight_style: ExRatatui.Style.t(),
          highlight_symbol: String.t() | nil,
          selected: non_neg_integer() | nil,
          direction: direction(),
          scroll_padding: non_neg_integer(),
          repeat_highlight_symbol: boolean()
        }

  defstruct items: [],
            style: %ExRatatui.Style{},
            block: nil,
            highlight_style: %ExRatatui.Style{},
            highlight_symbol: nil,
            selected: nil,
            direction: :top_to_bottom,
            scroll_padding: 0,
            repeat_highlight_symbol: false
end
