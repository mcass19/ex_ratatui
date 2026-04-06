defmodule ExRatatui.Widgets.ScrollView do
  @moduledoc """
  A viewport widget that clips and scrolls its content.

  Wraps any ExRatatui widget and provides scrolling functionality
  by rendering content to a buffer and blitting the visible portion.

  ## Examples

      iex> %ExRatatui.Widgets.ScrollView{}
      %ExRatatui.Widgets.ScrollView{
        widget: nil,
        content_height: 10,
        scroll_offset: 0,
        style: %ExRatatui.Style{},
        block: nil
      }

      iex> alias ExRatatui.Widgets.{ScrollView, Paragraph}
      iex> %ScrollView{
      ...>   widget: %Paragraph{text: "Line 1\\nLine 2\\nLine 3"},
      ...>   content_height: 20,
      ...>   scroll_offset: 5
      ...> }
      %ExRatatui.Widgets.ScrollView{
        widget: %ExRatatui.Widgets.Paragraph{text: "Line 1\\nLine 2\\nLine 3"},
        content_height: 20,
        scroll_offset: 5,
        style: %ExRatatui.Style{},
        block: nil
      }
  """

  alias ExRatatui.Style

  @type t :: %__MODULE__{
          widget: ExRatatui.widget() | nil,
          content_height: non_neg_integer(),
          scroll_offset: non_neg_integer(),
          style: Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct widget: nil,
            content_height: 10,
            scroll_offset: 0,
            style: %Style{},
            block: nil
end
