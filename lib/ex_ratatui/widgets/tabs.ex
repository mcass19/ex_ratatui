defmodule ExRatatui.Widgets.Tabs do
  @moduledoc """
  A tab bar widget for switching between views.

  ## Fields

    * `:titles` - list of tab title strings
    * `:selected` - zero-based index of the selected tab, or `nil` for no selection
    * `:style` - `%ExRatatui.Style{}` for non-selected tabs
    * `:highlight_style` - `%ExRatatui.Style{}` for the selected tab
    * `:divider` - separator string between tabs (default: `"|"`)
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container
    * `:padding` - `{left, right}` padding around each tab title (default: `{1, 1}`)

  ## Examples

      iex> %ExRatatui.Widgets.Tabs{titles: ["Tab 1", "Tab 2", "Tab 3"], selected: 0}
      %ExRatatui.Widgets.Tabs{
        titles: ["Tab 1", "Tab 2", "Tab 3"],
        selected: 0,
        style: %ExRatatui.Style{},
        highlight_style: %ExRatatui.Style{},
        divider: nil,
        block: nil,
        padding: {1, 1}
      }
  """

  @type t :: %__MODULE__{
          titles: [String.t()],
          selected: non_neg_integer() | nil,
          style: ExRatatui.Style.t(),
          highlight_style: ExRatatui.Style.t(),
          divider: String.t() | nil,
          block: ExRatatui.Widgets.Block.t() | nil,
          padding: {non_neg_integer(), non_neg_integer()}
        }

  defstruct titles: [],
            selected: nil,
            style: %ExRatatui.Style{},
            highlight_style: %ExRatatui.Style{},
            divider: nil,
            block: nil,
            padding: {1, 1}
end
