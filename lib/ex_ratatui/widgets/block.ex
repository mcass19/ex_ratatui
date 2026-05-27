defmodule ExRatatui.Widgets.Block do
  @moduledoc """
  A container widget that provides borders and titles around other widgets.

  Can be rendered standalone or used as the `:block` field on other widgets
  for composition. Supported by: Paragraph, List, Table, Gauge, LineGauge,
  Tabs, Checkbox, TextInput, Markdown, Textarea, Throbber, Popup, and WidgetList.

  ## Fields

    * `:title` - optional title displayed on the top border. Accepts any
      `ExRatatui.Text`-coercible line-like value: a `String.t()`, a
      `%ExRatatui.Text.Span{}`, a `%ExRatatui.Text.Line{}`, or a list of spans.
      Titles are single-line — strings with embedded newlines raise.
    * `:titles` - list of additional titles. Each entry is either a
      line-like value (uses the block's default position / alignment /
      style) or a `%ExRatatui.Widgets.Block.Title{}` carrying its own
      position, alignment, and style overrides. Combine with `:title`
      to model patterns like "filename | scroll %" — `:title` for the
      left side, plus a `%Block.Title{alignment: :right}` for the
      right side.
    * `:title_position` - `:top` (default) or `:bottom`. Default
      position for any title that does not carry its own.
    * `:title_alignment` - `:left` (default), `:center`, or `:right`.
      Default alignment for any title that does not carry its own.
    * `:title_style` - `%ExRatatui.Style{}` applied to every title
      that does not carry its own style.
    * `:borders` - list of border sides: `:all`, `:top`, `:right`, `:bottom`, `:left`
    * `:border_style` - `%ExRatatui.Style{}` for border color/modifiers
    * `:border_type` - `:plain`, `:rounded`, `:double`, or `:thick`
    * `:style` - `%ExRatatui.Style{}` for the inner area
    * `:padding` - `{left, right, top, bottom}` inner padding

  ## Examples

      iex> %ExRatatui.Widgets.Block{title: "My Panel", borders: [:all], border_type: :rounded}
      %ExRatatui.Widgets.Block{
        title: "My Panel",
        titles: [],
        title_position: :top,
        title_alignment: :left,
        title_style: nil,
        borders: [:all],
        border_style: %ExRatatui.Style{},
        border_type: :rounded,
        style: %ExRatatui.Style{},
        padding: {0, 0, 0, 0}
      }

      iex> alias ExRatatui.Widgets.Block
      iex> alias ExRatatui.Widgets.Block.Title
      iex> %Block{
      ...>   title: "src/lib.rs",
      ...>   titles: [%Title{content: "[3/12]", alignment: :right}],
      ...>   borders: [:all]
      ...> }
      %ExRatatui.Widgets.Block{
        title: "src/lib.rs",
        titles: [
          %ExRatatui.Widgets.Block.Title{
            content: "[3/12]",
            position: nil,
            alignment: :right,
            style: nil
          }
        ],
        title_position: :top,
        title_alignment: :left,
        title_style: nil,
        borders: [:all],
        border_style: %ExRatatui.Style{},
        border_type: :plain,
        style: %ExRatatui.Style{},
        padding: {0, 0, 0, 0}
      }
  """

  alias ExRatatui.Widgets.Block.Title

  @type border_side :: :all | :top | :right | :bottom | :left
  @type border_type :: :plain | :rounded | :double | :thick

  @type title ::
          String.t()
          | ExRatatui.Text.Span.t()
          | ExRatatui.Text.Line.t()
          | [ExRatatui.Text.Span.t()]

  @type title_entry :: title() | Title.t()

  @type t :: %__MODULE__{
          title: title() | nil,
          titles: [title_entry()],
          title_position: :top | :bottom,
          title_alignment: :left | :center | :right,
          title_style: ExRatatui.Style.t() | nil,
          borders: [border_side()],
          border_style: ExRatatui.Style.t(),
          border_type: border_type(),
          style: ExRatatui.Style.t(),
          padding: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
        }

  defstruct title: nil,
            titles: [],
            title_position: :top,
            title_alignment: :left,
            title_style: nil,
            borders: [],
            border_style: %ExRatatui.Style{},
            border_type: :plain,
            style: %ExRatatui.Style{},
            padding: {0, 0, 0, 0}
end
