defmodule ExRatatui.Widgets.Chart.Axis do
  @moduledoc """
  Configures one axis of a `ExRatatui.Widgets.Chart`.

  `:bounds` is required — it defines the visible coordinate range for
  this axis as `{min, max}`. Tick `:labels` are rendered along the axis
  in order; for a typical line chart you'd supply three labels (min,
  mid, max) for each axis.

  Labels accept the same string / `%Span{}` / `%Line{}` types used
  elsewhere in the library.

  ## Fields

    * `:title` - optional axis caption (string, `%Span{}`, or `%Line{}`)
    * `:bounds` - required `{min, max}` numeric tuple
    * `:labels` - list of tick labels (default `[]`)
    * `:style` - `%ExRatatui.Style{}` for the axis line and labels
    * `:labels_alignment` - `:left` (default), `:center`, or `:right`

  ## Examples

      iex> alias ExRatatui.Widgets.Chart.Axis
      iex> %Axis{title: "X", bounds: {0.0, 10.0}, labels: ["0", "5", "10"]}
      %ExRatatui.Widgets.Chart.Axis{
        title: "X",
        bounds: {0.0, 10.0},
        labels: ["0", "5", "10"],
        style: %ExRatatui.Style{},
        labels_alignment: :left
      }
  """

  @type alignment :: :left | :center | :right

  @type line_like :: String.t() | ExRatatui.Text.Span.t() | ExRatatui.Text.Line.t()

  @type t :: %__MODULE__{
          title: line_like() | nil,
          bounds: {number(), number()},
          labels: [line_like()],
          style: ExRatatui.Style.t(),
          labels_alignment: alignment()
        }

  defstruct title: nil,
            bounds: nil,
            labels: [],
            style: %ExRatatui.Style{},
            labels_alignment: :left
end
