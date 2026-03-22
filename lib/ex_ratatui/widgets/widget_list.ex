defmodule ExRatatui.Widgets.WidgetList do
  @moduledoc """
  A vertical list of heterogeneous widgets with optional selection and scrolling.

  Each item is a `{widget, height}` tuple where `widget` is any ExRatatui widget
  and `height` is the number of rows that item occupies. Items can have different
  heights, making this ideal for chat message histories.

  ## Examples

      alias ExRatatui.Widgets.{WidgetList, Paragraph, Markdown, Block}

      %WidgetList{
        items: [
          {%Paragraph{text: "User: Hello!"}, 1},
          {%Markdown{content: "**Bot:** Hi there!\\n\\nHow can I help?"}, 4},
          {%Paragraph{text: "User: What is Elixir?"}, 1}
        ],
        selected: 1,
        scroll_offset: 0,
        block: %Block{title: "Chat", borders: [:all]}
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
