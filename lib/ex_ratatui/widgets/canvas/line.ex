defmodule ExRatatui.Widgets.Canvas.Line do
  @moduledoc """
  A line segment to paint on a `ExRatatui.Widgets.Canvas`.

  Coordinates are expressed in the canvas' own coordinate system (the
  space defined by `:x_bounds` and `:y_bounds`), not terminal cells.

  ## Fields

    * `:x1` - starting x coordinate (required)
    * `:y1` - starting y coordinate (required)
    * `:x2` - ending x coordinate (required)
    * `:y2` - ending y coordinate (required)
    * `:color` - `ExRatatui.Style.color()` for the line (required)

  ## Examples

      iex> alias ExRatatui.Widgets.Canvas.Line
      iex> %Line{x1: 0.0, y1: 0.0, x2: 10.0, y2: 10.0, color: :red}
      %ExRatatui.Widgets.Canvas.Line{
        x1: 0.0,
        y1: 0.0,
        x2: 10.0,
        y2: 10.0,
        color: :red
      }
  """

  @type t :: %__MODULE__{
          x1: number(),
          y1: number(),
          x2: number(),
          y2: number(),
          color: ExRatatui.Style.color()
        }

  defstruct x1: nil, y1: nil, x2: nil, y2: nil, color: nil
end
