defmodule ExRatatui.Widgets.WidgetList do
  @moduledoc """
  A vertical list of heterogeneous widgets with optional selection and scrolling.

  Each item is a `{widget, height}` tuple where `widget` is any ExRatatui widget
  and `height` is the number of rows that item occupies. Items can have different
  heights, making this ideal for chat message histories.

  `scroll_offset` is a **row offset** from the top of the content. To scroll to
  a specific widget, sum the heights of all preceding items. Items partially above
  the viewport are clipped at the row level.

  ## Examples

      iex> %ExRatatui.Widgets.WidgetList{}
      %ExRatatui.Widgets.WidgetList{
        items: [],
        selected: nil,
        highlight_style: %ExRatatui.Style{},
        scroll_offset: 0,
        style: %ExRatatui.Style{},
        block: nil
      }

      iex> alias ExRatatui.Widgets.{WidgetList, Paragraph, Block}
      iex> %WidgetList{
      ...>   items: [
      ...>     {%Paragraph{text: "First message"}, 1},
      ...>     {%Paragraph{text: "Second message"}, 1}
      ...>   ],
      ...>   selected: 0,
      ...>   block: %Block{title: "Chat", borders: [:all]}
      ...> }
      %ExRatatui.Widgets.WidgetList{
        items: [
          {%ExRatatui.Widgets.Paragraph{text: "First message"}, 1},
          {%ExRatatui.Widgets.Paragraph{text: "Second message"}, 1}
        ],
        selected: 0,
        highlight_style: %ExRatatui.Style{},
        scroll_offset: 0,
        style: %ExRatatui.Style{},
        block: %ExRatatui.Widgets.Block{title: "Chat", borders: [:all]}
      }
  """

  alias ExRatatui.Style

  @type t :: %__MODULE__{
          items: [{ExRatatui.widget(), non_neg_integer()}],
          selected: non_neg_integer() | nil,
          highlight_style: Style.t(),
          scroll_offset: non_neg_integer(),
          style: Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct items: [],
            selected: nil,
            highlight_style: %Style{},
            scroll_offset: 0,
            style: %Style{},
            block: nil
end
