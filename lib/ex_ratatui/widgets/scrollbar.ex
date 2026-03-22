defmodule ExRatatui.Widgets.Scrollbar do
  @moduledoc """
  A scrollbar widget for indicating scroll position in content.

  ## Fields

    * `:orientation` - one of `:vertical_right` (default), `:vertical_left`,
      `:horizontal_bottom`, `:horizontal_top`
    * `:content_length` - total number of scrollable items or lines
    * `:position` - current scroll position (zero-based)
    * `:viewport_content_length` - number of visible items (optional, improves thumb sizing)
    * `:thumb_style` - `%ExRatatui.Style{}` for the scrollbar thumb
    * `:track_style` - `%ExRatatui.Style{}` for the scrollbar track
    * `:thumb_symbol` - custom character for the thumb (optional)
    * `:track_symbol` - custom character for the track (optional)
    * `:begin_symbol` - custom character for the start arrow (optional)
    * `:end_symbol` - custom character for the end arrow (optional)

  ## Examples

      iex> %ExRatatui.Widgets.Scrollbar{content_length: 100, position: 25}
      %ExRatatui.Widgets.Scrollbar{
        orientation: :vertical_right,
        content_length: 100,
        position: 25,
        viewport_content_length: nil,
        thumb_style: %ExRatatui.Style{},
        track_style: %ExRatatui.Style{},
        thumb_symbol: nil,
        track_symbol: nil,
        begin_symbol: nil,
        end_symbol: nil
      }
  """

  @type orientation ::
          :vertical_right | :vertical_left | :horizontal_bottom | :horizontal_top

  @type t :: %__MODULE__{
          orientation: orientation(),
          content_length: non_neg_integer(),
          position: non_neg_integer(),
          viewport_content_length: non_neg_integer() | nil,
          thumb_style: ExRatatui.Style.t(),
          track_style: ExRatatui.Style.t(),
          thumb_symbol: String.t() | nil,
          track_symbol: String.t() | nil,
          begin_symbol: String.t() | nil,
          end_symbol: String.t() | nil
        }

  defstruct orientation: :vertical_right,
            content_length: 0,
            position: 0,
            viewport_content_length: nil,
            thumb_style: %ExRatatui.Style{},
            track_style: %ExRatatui.Style{},
            thumb_symbol: nil,
            track_symbol: nil,
            begin_symbol: nil,
            end_symbol: nil
end
