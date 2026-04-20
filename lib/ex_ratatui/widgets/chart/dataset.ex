defmodule ExRatatui.Widgets.Chart.Dataset do
  @moduledoc """
  A single named series within a `ExRatatui.Widgets.Chart`.

  Each dataset owns its `(x, y)` points and decides how they're drawn —
  the chart's role is to supply the axes, legend, and surrounding
  block. Multiple datasets render together in the same chart area, so
  scale them against shared `:x_axis` / `:y_axis` bounds.

  ## Fields

    * `:name` - legend caption; `nil` excludes the dataset from the legend
    * `:data` - list of `{x, y}` numeric tuples (required, may be empty)
    * `:marker` - one of `:braille` (default), `:dot`, `:block`, `:bar`,
      `:half_block`
    * `:graph_type` - one of `:line` (default), `:scatter`, `:bar`
    * `:style` - `%ExRatatui.Style{}` controlling line/marker color

  ## Examples

      iex> alias ExRatatui.Widgets.Chart.Dataset
      iex> %Dataset{name: "temp", data: [{0.0, 12.0}, {1.0, 14.0}]}
      %ExRatatui.Widgets.Chart.Dataset{
        name: "temp",
        data: [{0.0, 12.0}, {1.0, 14.0}],
        marker: :braille,
        graph_type: :line,
        style: %ExRatatui.Style{}
      }
  """

  @type marker :: :braille | :dot | :block | :bar | :half_block
  @type graph_type :: :line | :scatter | :bar

  @type t :: %__MODULE__{
          name: String.t() | nil,
          data: [{number(), number()}],
          marker: marker(),
          graph_type: graph_type(),
          style: ExRatatui.Style.t()
        }

  defstruct name: nil,
            data: [],
            marker: :braille,
            graph_type: :line,
            style: %ExRatatui.Style{}
end
