defmodule ExRatatui.Widgets.Calendar do
  @moduledoc """
  A monthly calendar widget that displays days in a 7-column grid.

  Wraps Ratatui's `Monthly` widget. `:display_date` picks the month to render
  (the day component only matters for surrounding-month styling around boundaries).
  Per-day highlights are expressed through `:events` — either a list of
  `{Date.t(), Style.t()}` tuples (later entries win on duplicate dates) or a
  `%{Date.t() => Style.t()}` map.

  ## Fields

    * `:display_date` - `Date.t()` inside the month to display (required)
    * `:events` - per-day style overrides, applied on top of `:default_style`.
      Accepts either a list of `{Date, Style}` tuples or a `%{Date => Style}` map
    * `:default_style` - `%ExRatatui.Style{}` applied to every cell as the baseline
    * `:show_month_header` - boolean, default `true`; renders the "Month YYYY" header
    * `:header_style` - `%ExRatatui.Style{}` for the month header
    * `:show_weekdays_header` - boolean, default `true`; renders the "Su Mo Tu..." row
    * `:weekday_style` - `%ExRatatui.Style{}` for the weekdays row
    * `:show_surrounding` - `%ExRatatui.Style{}` applied to previous/next month days
      (nil hides them)
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container

  ## Examples

      iex> alias ExRatatui.Widgets.Calendar
      iex> %Calendar{display_date: ~D[2026-03-15]}
      %ExRatatui.Widgets.Calendar{
        display_date: ~D[2026-03-15],
        events: nil,
        default_style: nil,
        show_month_header: true,
        header_style: nil,
        show_weekdays_header: true,
        weekday_style: nil,
        show_surrounding: nil,
        block: nil
      }
  """

  @type events ::
          [{Date.t(), ExRatatui.Style.t()}]
          | %{Date.t() => ExRatatui.Style.t()}
          | nil

  @type t :: %__MODULE__{
          display_date: Date.t(),
          events: events(),
          default_style: ExRatatui.Style.t() | nil,
          show_month_header: boolean(),
          header_style: ExRatatui.Style.t() | nil,
          show_weekdays_header: boolean(),
          weekday_style: ExRatatui.Style.t() | nil,
          show_surrounding: ExRatatui.Style.t() | nil,
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct display_date: nil,
            events: nil,
            default_style: nil,
            show_month_header: true,
            header_style: nil,
            show_weekdays_header: true,
            weekday_style: nil,
            show_surrounding: nil,
            block: nil
end
