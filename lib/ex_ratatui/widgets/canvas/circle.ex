defmodule ExRatatui.Widgets.Canvas.Circle do
  @moduledoc """
  A circle outline to paint on a `ExRatatui.Widgets.Canvas`.

  `:x` and `:y` pin the **center** in canvas coordinates. Only the
  circumference is drawn (ratatui's Canvas shape has no fill).

  ## Fields

    * `:x` - center x coordinate (required)
    * `:y` - center y coordinate (required)
    * `:radius` - non-negative radius in canvas units (required)
    * `:color` - `ExRatatui.Style.color()` for the outline (required)

  ## Examples

      iex> alias ExRatatui.Widgets.Canvas.Circle
      iex> %Circle{x: 5.0, y: 5.0, radius: 3.0, color: :yellow}
      %ExRatatui.Widgets.Canvas.Circle{
        x: 5.0,
        y: 5.0,
        radius: 3.0,
        color: :yellow
      }
  """

  @type t :: %__MODULE__{
          x: number(),
          y: number(),
          radius: number(),
          color: ExRatatui.Style.color()
        }

  defstruct x: nil, y: nil, radius: nil, color: nil
end
