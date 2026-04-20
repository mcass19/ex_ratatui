defmodule ExRatatui.Widgets.Canvas do
  @moduledoc """
  A 2D drawing surface for plotting shapes in arbitrary coordinate space.

  Wraps Ratatui's `Canvas` widget. Define the coordinate window with
  `:x_bounds` and `:y_bounds` — both `{min, max}` tuples — and paint
  into it by listing shape structs in `:shapes`. Each shape carries its
  own color; the canvas only controls the marker resolution and the
  optional background wash.

  Supported shapes live under `ExRatatui.Widgets.Canvas.*`:

    * `Line`      - `%Line{x1, y1, x2, y2, color}`
    * `Rectangle` - `%Rectangle{x, y, width, height, color}` (bottom-left anchored, outline only)
    * `Circle`    - `%Circle{x, y, radius, color}` (center anchored, outline only)
    * `Points`    - `%Points{coords: [{x, y}], color}`

  ## Markers

  The `:marker` controls how canvas coordinates map to cell pixels:

    * `:braille` (default) - 2×4 sub-cell pixels, best for lines/curves
    * `:dot`               - one glyph per cell
    * `:block`             - solid block, good for heatmaps
    * `:bar`               - half-height bar
    * `:half_block`        - 1×2 sub-cell pixels

  ## Fields

    * `:x_bounds` - `{min, max}` tuple bounding the X axis (required)
    * `:y_bounds` - `{min, max}` tuple bounding the Y axis (required)
    * `:marker` - one of `:braille`, `:dot`, `:block`, `:bar`, `:half_block`
      (default `:braille`)
    * `:background_color` - `ExRatatui.Style.color()` washed behind shapes; `nil`
      falls back to the terminal default
    * `:shapes` - list of shape structs (default `[]`)
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container

  ## Examples

      iex> alias ExRatatui.Widgets.Canvas
      iex> alias ExRatatui.Widgets.Canvas.Line
      iex> %Canvas{
      ...>   x_bounds: {0.0, 10.0},
      ...>   y_bounds: {0.0, 10.0},
      ...>   shapes: [%Line{x1: 0.0, y1: 0.0, x2: 10.0, y2: 10.0, color: :red}]
      ...> }
      %ExRatatui.Widgets.Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        marker: :braille,
        background_color: nil,
        shapes: [
          %ExRatatui.Widgets.Canvas.Line{x1: 0.0, y1: 0.0, x2: 10.0, y2: 10.0, color: :red}
        ],
        block: nil
      }
  """

  alias ExRatatui.Widgets.Canvas.{Circle, Line, Points, Rectangle}

  @type marker :: :braille | :dot | :block | :bar | :half_block

  @type shape :: Line.t() | Rectangle.t() | Circle.t() | Points.t()

  @type t :: %__MODULE__{
          x_bounds: {number(), number()},
          y_bounds: {number(), number()},
          marker: marker(),
          background_color: ExRatatui.Style.color() | nil,
          shapes: [shape()],
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct x_bounds: nil,
            y_bounds: nil,
            marker: :braille,
            background_color: nil,
            shapes: [],
            block: nil
end
