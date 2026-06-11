defmodule ExRatatui.Widgets.BarGroup do
  @moduledoc """
  A labelled cluster of `ExRatatui.Widgets.Bar` rendered together inside a
  `ExRatatui.Widgets.BarChart`.

  Use groups to show several related bars side by side
  with a shared caption — comparing the same metrics across categories,
  for example. Set `BarChart.groups` to `[%BarGroup{}, ...]` instead of
  the flat `:data` list; the chart will draw each group as a cluster
  separated by `BarChart.group_gap` cells.

  ## Fields

    * `:label` - optional caption rendered under the cluster; `nil`
      omits it
    * `:bars` - list of `%ExRatatui.Widgets.Bar{}` belonging to the
      group (required; may be empty)

  ## Examples

      iex> alias ExRatatui.Widgets.{Bar, BarGroup}
      iex> %BarGroup{label: "Q1", bars: [%Bar{label: "A", value: 5}]}
      %ExRatatui.Widgets.BarGroup{
        label: "Q1",
        bars: [%ExRatatui.Widgets.Bar{label: "A", value: 5, style: nil, text_value: nil}]
      }
  """

  @type t :: %__MODULE__{
          label: String.t() | nil,
          bars: [ExRatatui.Widgets.Bar.t()]
        }

  defstruct label: nil, bars: []
end
