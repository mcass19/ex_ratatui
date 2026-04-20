defmodule ExRatatui.Widgets.Chart do
  @moduledoc """
  An XY plotting widget for line, scatter, and bar visualizations.

  Wraps Ratatui's `Chart` widget. Each `:datasets` entry is a
  `ExRatatui.Widgets.Chart.Dataset` struct carrying its own `(x, y)`
  pairs, marker, graph type, and color. Both axes are required and
  configured via `ExRatatui.Widgets.Chart.Axis` structs — the caller
  controls `:bounds`, optional `:title`, tick `:labels`, and label
  alignment.

  ## Graph types

  Each dataset chooses how its points are drawn:

    * `:line`    - connects consecutive points with line segments
    * `:scatter` - draws one marker per point (default-friendly for
      sparse data)
    * `:bar`     - draws a vertical bar from the X axis up to each
      point

  ## Markers

  The `:marker` on each dataset controls cell-level pixel resolution.
  Valid values mirror `ExRatatui.Widgets.Canvas`: `:braille` (default),
  `:dot`, `:block`, `:bar`, `:half_block`.

  ## Legend

  `:legend_position` accepts `:top`, `:top_left`, `:top_right` (default),
  `:bottom`, `:bottom_left`, `:bottom_right`, `:left`, `:right`, or
  `nil` to hide the legend entirely. `:hidden_legend_constraints`
  takes a `{horizontal, vertical}` tuple of `Constraint`s describing
  the smallest area in which the legend will still render — handy when
  the chart shrinks below a usable size.

  ## Fields

    * `:datasets` - list of `%ExRatatui.Widgets.Chart.Dataset{}` (default `[]`)
    * `:x_axis` - required `%ExRatatui.Widgets.Chart.Axis{}`
    * `:y_axis` - required `%ExRatatui.Widgets.Chart.Axis{}`
    * `:legend_position` - position atom (default `:top_right`) or `nil` to hide
    * `:hidden_legend_constraints` - `{Constraint.t(), Constraint.t()}` or `nil`
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container

  ## Examples

      iex> alias ExRatatui.Widgets.Chart
      iex> alias ExRatatui.Widgets.Chart.{Axis, Dataset}
      iex> %Chart{
      ...>   datasets: [%Dataset{name: "cpu", data: [{0.0, 1.0}, {1.0, 2.0}]}],
      ...>   x_axis: %Axis{bounds: {0.0, 10.0}},
      ...>   y_axis: %Axis{bounds: {0.0, 10.0}}
      ...> }
      %ExRatatui.Widgets.Chart{
        datasets: [
          %ExRatatui.Widgets.Chart.Dataset{
            name: "cpu",
            data: [{0.0, 1.0}, {1.0, 2.0}],
            marker: :braille,
            graph_type: :line,
            style: %ExRatatui.Style{}
          }
        ],
        x_axis: %ExRatatui.Widgets.Chart.Axis{
          title: nil,
          bounds: {0.0, 10.0},
          labels: [],
          style: %ExRatatui.Style{},
          labels_alignment: :left
        },
        y_axis: %ExRatatui.Widgets.Chart.Axis{
          title: nil,
          bounds: {0.0, 10.0},
          labels: [],
          style: %ExRatatui.Style{},
          labels_alignment: :left
        },
        legend_position: :top_right,
        hidden_legend_constraints: nil,
        block: nil
      }
  """

  alias ExRatatui.Widgets.Chart.{Axis, Dataset}

  @type legend_position ::
          :top
          | :top_left
          | :top_right
          | :bottom
          | :bottom_left
          | :bottom_right
          | :left
          | :right
          | nil

  @type t :: %__MODULE__{
          datasets: [Dataset.t()],
          x_axis: Axis.t(),
          y_axis: Axis.t(),
          legend_position: legend_position(),
          hidden_legend_constraints:
            {ExRatatui.Layout.constraint(), ExRatatui.Layout.constraint()} | nil,
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct datasets: [],
            x_axis: nil,
            y_axis: nil,
            legend_position: :top_right,
            hidden_legend_constraints: nil,
            block: nil
end
