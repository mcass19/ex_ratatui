defmodule ExRatatui.Widgets.Sparkline do
  @moduledoc """
  A compact inline chart for a single data series.

  Each entry in `:data` is either a non-negative integer sample or `nil` for
  a missing/absent sample. Absent samples render with the configurable
  `:absent_value_symbol` (default `" "`) and `:absent_value_style`, which
  distinguishes gaps from zeros.

  ## Fields

    * `:data` - list of `non_neg_integer() | nil` samples (required; may be empty)
    * `:style` - chart-wide `%ExRatatui.Style{}`; falls back to terminal default
    * `:max` - optional upper bound; when `nil`, the chart auto-scales to the largest value
    * `:direction` - `:left_to_right` (default) or `:right_to_left`
    * `:bar_set` - glyph set used to draw the bars:
      * `:nine_levels` (default, full-block gradient)
      * `:three_levels` (low/medium/high)
      * a list of strings from empty to full, e.g. `[" ", "▂", "▅", "█"]`
    * `:absent_value_style` - `%ExRatatui.Style{}` applied to gap cells
    * `:absent_value_symbol` - grapheme rendered for `nil` samples (default `" "`)
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container

  ## Examples

      iex> alias ExRatatui.Widgets.Sparkline
      iex> %Sparkline{data: [0, 1, 3, 7, 3, 1, 0]}
      %ExRatatui.Widgets.Sparkline{
        data: [0, 1, 3, 7, 3, 1, 0],
        style: nil,
        max: nil,
        direction: :left_to_right,
        bar_set: :nine_levels,
        absent_value_style: nil,
        absent_value_symbol: nil,
        block: nil
      }
  """

  @type direction :: :left_to_right | :right_to_left
  @type bar_set :: :nine_levels | :three_levels | [String.t()]

  @type t :: %__MODULE__{
          data: [non_neg_integer() | nil],
          style: ExRatatui.Style.t() | nil,
          max: nil | non_neg_integer(),
          direction: direction(),
          bar_set: bar_set(),
          absent_value_style: ExRatatui.Style.t() | nil,
          absent_value_symbol: String.t() | nil,
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct data: [],
            style: nil,
            max: nil,
            direction: :left_to_right,
            bar_set: :nine_levels,
            absent_value_style: nil,
            absent_value_symbol: nil,
            block: nil
end
