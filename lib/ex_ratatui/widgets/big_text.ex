defmodule ExRatatui.Widgets.BigText do
  @moduledoc """
  An oversized 8×8-pixel text widget for slide titles and banners.

  Backed by [tui-big-text](https://github.com/ratatui/tui-widgets/tree/main/tui-big-text),
  which rasterises each character through the `font8x8` bitmap font.
  Useful for slide deck headers, splash screens, end-of-game banners,
  and anywhere a regular paragraph won't carry across a 10-foot room.

  Build the widget with `ExRatatui.BigText.new/2`; raw struct
  construction is supported but skips input coercion.

  ## Fields

    * `:lines` - list of `%ExRatatui.Text.Line{}` to render. The pixel
      grid is laid out top to bottom; styling on a line or its spans
      paints the corresponding glyph cells.
    * `:pixel_size` - how many character cells a single 8×8-pixel glyph
      occupies. One of `:full` (1 cell per pixel, the default),
      `:half_height`, `:half_width`, `:quadrant`, `:third_height`,
      `:sextant`, `:quarter_height`, `:octant`. Smaller pixel sizes pack
      more characters into the same area; `:octant` is the densest.
    * `:alignment` - `:left`, `:center`, or `:right`. Default `:left`.
    * `:style` - `%ExRatatui.Style{}` applied as the outermost default
      style. Per-line / per-span styles win on conflict.
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container. We
      render the block border first and confine the big-text grid to
      the inner area.

  ## Example

      iex> alias ExRatatui.Widgets.BigText
      iex> alias ExRatatui.Text.{Line, Span}
      iex> alias ExRatatui.Style
      iex> %BigText{
      ...>   lines: [%Line{spans: [%Span{content: "EX_RATATUI"}]}],
      ...>   pixel_size: :half_height,
      ...>   alignment: :center,
      ...>   style: %Style{fg: :magenta}
      ...> }
      %ExRatatui.Widgets.BigText{
        lines: [
          %ExRatatui.Text.Line{
            spans: [%ExRatatui.Text.Span{content: "EX_RATATUI", style: %ExRatatui.Style{}}],
            style: %ExRatatui.Style{},
            alignment: nil
          }
        ],
        pixel_size: :half_height,
        alignment: :center,
        style: %ExRatatui.Style{fg: :magenta, bg: nil, modifiers: []},
        block: nil
      }
  """

  @type pixel_size ::
          :full
          | :half_height
          | :half_width
          | :quadrant
          | :third_height
          | :sextant
          | :quarter_height
          | :octant

  @type alignment :: :left | :center | :right

  @type t :: %__MODULE__{
          lines: [ExRatatui.Text.Line.t()],
          pixel_size: pixel_size(),
          alignment: alignment(),
          style: ExRatatui.Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct lines: [],
            pixel_size: :full,
            alignment: :left,
            style: %ExRatatui.Style{},
            block: nil
end
