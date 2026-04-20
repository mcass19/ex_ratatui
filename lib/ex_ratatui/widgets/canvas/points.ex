defmodule ExRatatui.Widgets.Canvas.Points do
  @moduledoc """
  A collection of single-point markers to paint on a `ExRatatui.Widgets.Canvas`.

  Each entry in `:coords` is a `{x, y}` tuple in canvas coordinates — great
  for scatter plots, cursor overlays, or starfield-like decorations.

  ## Fields

    * `:coords` - list of `{number, number}` tuples (required; may be empty)
    * `:color` - `ExRatatui.Style.color()` applied to every point (required)

  ## Examples

      iex> alias ExRatatui.Widgets.Canvas.Points
      iex> %Points{coords: [{1.0, 1.0}, {2.0, 3.0}], color: :green}
      %ExRatatui.Widgets.Canvas.Points{
        coords: [{1.0, 1.0}, {2.0, 3.0}],
        color: :green
      }
  """

  @type t :: %__MODULE__{
          coords: [{number(), number()}],
          color: ExRatatui.Style.color()
        }

  defstruct coords: [], color: nil
end
