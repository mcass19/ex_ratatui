defmodule ExRatatui.Widgets.BarChart do
  @moduledoc """
  A vertical or horizontal bar chart widget.

  Each entry in `:data` is a `ExRatatui.Widgets.Bar` struct carrying a label
  and a non-negative integer value. Chart-level `:bar_style`, `:value_style`,
  and `:label_style` apply to every bar by default; individual bars can
  override their color via their own `:style` field, or replace the numeric
  display via `:text_value`.

  ## Fields

    * `:data` - list of `%ExRatatui.Widgets.Bar{}` (required; may be empty)
    * `:bar_width` - width (vertical) or height (horizontal) of each bar in cells; default `1`
    * `:bar_gap` - cells between adjacent bars; default `1`
    * `:bar_style` - shared `%ExRatatui.Style{}` applied to bars without a per-bar override
    * `:value_style` - `%ExRatatui.Style{}` for the numeric value text
    * `:label_style` - `%ExRatatui.Style{}` for bar labels
    * `:max` - optional upper bound; when `nil`, the chart auto-scales to the largest value
    * `:direction` - `:vertical` (default) or `:horizontal`
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container

  ## Examples

      iex> alias ExRatatui.Widgets.{Bar, BarChart}
      iex> %BarChart{data: [%Bar{label: "Elixir", value: 80}, %Bar{label: "Rust", value: 95}]}
      %ExRatatui.Widgets.BarChart{
        data: [
          %ExRatatui.Widgets.Bar{label: "Elixir", value: 80, style: nil, text_value: nil},
          %ExRatatui.Widgets.Bar{label: "Rust", value: 95, style: nil, text_value: nil}
        ],
        bar_width: 1,
        bar_gap: 1,
        bar_style: %ExRatatui.Style{},
        value_style: %ExRatatui.Style{},
        label_style: %ExRatatui.Style{},
        max: nil,
        direction: :vertical,
        block: nil
      }
  """

  @type direction :: :vertical | :horizontal

  @type t :: %__MODULE__{
          data: [ExRatatui.Widgets.Bar.t()],
          bar_width: pos_integer(),
          bar_gap: non_neg_integer(),
          bar_style: ExRatatui.Style.t(),
          value_style: ExRatatui.Style.t(),
          label_style: ExRatatui.Style.t(),
          max: nil | non_neg_integer(),
          direction: direction(),
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct data: [],
            bar_width: 1,
            bar_gap: 1,
            bar_style: %ExRatatui.Style{},
            value_style: %ExRatatui.Style{},
            label_style: %ExRatatui.Style{},
            max: nil,
            direction: :vertical,
            block: nil
end
