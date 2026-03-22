defmodule ExRatatui.Widgets.LineGauge do
  @moduledoc """
  A thin horizontal progress bar widget.

  Similar to `ExRatatui.Widgets.Gauge` but renders as a single line using
  line-drawing characters.

  ## Fields

    * `:ratio` - progress value from `0.0` to `1.0` (clamped automatically)
    * `:label` - optional label string displayed alongside the gauge
    * `:style` - `%ExRatatui.Style{}` for the widget background
    * `:filled_style` - `%ExRatatui.Style{}` for the filled portion
    * `:unfilled_style` - `%ExRatatui.Style{}` for the unfilled portion
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container

  ## Examples

      iex> %ExRatatui.Widgets.LineGauge{ratio: 0.6, label: "60%"}
      %ExRatatui.Widgets.LineGauge{
        ratio: 0.6,
        label: "60%",
        style: %ExRatatui.Style{},
        filled_style: %ExRatatui.Style{},
        unfilled_style: %ExRatatui.Style{},
        block: nil
      }
  """

  @type t :: %__MODULE__{
          ratio: float(),
          label: String.t() | nil,
          style: ExRatatui.Style.t(),
          filled_style: ExRatatui.Style.t(),
          unfilled_style: ExRatatui.Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct ratio: 0.0,
            label: nil,
            style: %ExRatatui.Style{},
            filled_style: %ExRatatui.Style{},
            unfilled_style: %ExRatatui.Style{},
            block: nil
end
