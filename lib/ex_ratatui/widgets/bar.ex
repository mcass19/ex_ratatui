defmodule ExRatatui.Widgets.Bar do
  @moduledoc """
  A single bar within a `ExRatatui.Widgets.BarChart`.

  ## Fields

    * `:label` - plain string shown next to the bar (required)
    * `:value` - non-negative integer the bar length is scaled against (required)
    * `:style` - optional `%ExRatatui.Style{}` overriding the chart's shared `bar_style`
    * `:text_value` - optional string replacing the rendered numeric value
      (e.g. `"80%"` or `"$42k"`); when `nil`, `value` is rendered as-is

  ## Examples

      iex> %ExRatatui.Widgets.Bar{label: "Elixir", value: 80}
      %ExRatatui.Widgets.Bar{
        label: "Elixir",
        value: 80,
        style: nil,
        text_value: nil
      }
  """

  @type t :: %__MODULE__{
          label: String.t(),
          value: non_neg_integer(),
          style: ExRatatui.Style.t() | nil,
          text_value: String.t() | nil
        }

  defstruct label: "",
            value: 0,
            style: nil,
            text_value: nil
end
