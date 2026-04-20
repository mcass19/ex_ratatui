defmodule ExRatatui.Widgets.Canvas.Rectangle do
  @moduledoc """
  A rectangle outline to paint on a `ExRatatui.Widgets.Canvas`.

  `:x` and `:y` pin the **bottom-left** corner in canvas coordinates —
  not terminal cells. Only the border is drawn (ratatui's Canvas shape
  has no fill).

  ## Fields

    * `:x` - bottom-left x coordinate (required)
    * `:y` - bottom-left y coordinate (required)
    * `:width` - non-negative width in canvas units (required)
    * `:height` - non-negative height in canvas units (required)
    * `:color` - `ExRatatui.Style.color()` for the outline (required)

  ## Examples

      iex> alias ExRatatui.Widgets.Canvas.Rectangle
      iex> %Rectangle{x: 0.0, y: 0.0, width: 5.0, height: 3.0, color: :blue}
      %ExRatatui.Widgets.Canvas.Rectangle{
        x: 0.0,
        y: 0.0,
        width: 5.0,
        height: 3.0,
        color: :blue
      }
  """

  @type t :: %__MODULE__{
          x: number(),
          y: number(),
          width: number(),
          height: number(),
          color: ExRatatui.Style.color()
        }

  defstruct x: nil, y: nil, width: nil, height: nil, color: nil
end
