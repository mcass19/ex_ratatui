defmodule ExRatatui.Widgets.Block do
  @moduledoc """
  A container widget that provides borders and a title around other widgets.

  Can be rendered standalone or used as the `:block` field on other widgets
  for composition. Supported by: Paragraph, List, Table, Gauge, LineGauge,
  Tabs, Checkbox, TextInput, Markdown, Textarea, Throbber, Popup, and WidgetList.

  ## Fields

    * `:title` - optional title displayed on the top border. Accepts any
      `ExRatatui.Text`-coercible line-like value: a `String.t()`, a
      `%ExRatatui.Text.Span{}`, a `%ExRatatui.Text.Line{}`, or a list of spans.
      Titles are single-line — strings with embedded newlines raise.
    * `:borders` - list of border sides: `:all`, `:top`, `:right`, `:bottom`, `:left`
    * `:border_style` - `%ExRatatui.Style{}` for border color/modifiers
    * `:border_type` - `:plain`, `:rounded`, `:double`, or `:thick`
    * `:style` - `%ExRatatui.Style{}` for the inner area
    * `:padding` - `{left, right, top, bottom}` inner padding

  ## Examples

      iex> %ExRatatui.Widgets.Block{title: "My Panel", borders: [:all], border_type: :rounded}
      %ExRatatui.Widgets.Block{
        title: "My Panel",
        borders: [:all],
        border_style: %ExRatatui.Style{},
        border_type: :rounded,
        style: %ExRatatui.Style{},
        padding: {0, 0, 0, 0}
      }

      iex> %ExRatatui.Widgets.Block{}
      %ExRatatui.Widgets.Block{
        title: nil,
        borders: [],
        border_style: %ExRatatui.Style{},
        border_type: :plain,
        style: %ExRatatui.Style{},
        padding: {0, 0, 0, 0}
      }
  """

  @type border_side :: :all | :top | :right | :bottom | :left
  @type border_type :: :plain | :rounded | :double | :thick

  @type title ::
          String.t()
          | ExRatatui.Text.Span.t()
          | ExRatatui.Text.Line.t()
          | [ExRatatui.Text.Span.t()]

  @type t :: %__MODULE__{
          title: title() | nil,
          borders: [border_side()],
          border_style: ExRatatui.Style.t(),
          border_type: border_type(),
          style: ExRatatui.Style.t(),
          padding: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
        }

  defstruct title: nil,
            borders: [],
            border_style: %ExRatatui.Style{},
            border_type: :plain,
            style: %ExRatatui.Style{},
            padding: {0, 0, 0, 0}
end
