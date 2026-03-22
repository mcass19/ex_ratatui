defmodule ExRatatui.Widgets.Throbber do
  @moduledoc """
  A loading spinner widget that animates through symbol sets.

  Uses the `throbber-widgets-tui` Rust crate for rendering. The caller
  controls the animation by incrementing the `:step` value (typically
  on each tick or timer event).

  ## Animation sets

  The `:throbber_set` option selects the symbol animation:

    * `:braille` (default) — braille dot patterns (⠷ ⠯ ⠟ ⠻ ⠽ ⠾)
    * `:dots` — braille double dots
    * `:ascii` — classic spinner (| / - \\)
    * `:vertical_block` — growing vertical block (▁ ▂ ▃ … █)
    * `:horizontal_block` — growing horizontal block (▏ ▎ ▍ … █)
    * `:arrow` — rotating arrow (↑ ↗ → ↘ ↓ ↙ ← ↖)
    * `:clock` — clock emoji animation
    * `:box_drawing` — box-drawing rotation
    * `:black_circle` — rotating black circle
    * `:white_circle` — rotating white circle
    * `:white_square` — rotating white square
    * `:quadrant_block` — quadrant block rotation

  ## Examples

      iex> alias ExRatatui.Widgets.Throbber
      iex> %Throbber{label: "Loading...", step: 0}
      %Throbber{label: "Loading...", step: 0, throbber_set: :braille, style: %ExRatatui.Style{}, throbber_style: %ExRatatui.Style{}, block: nil}
  """

  alias ExRatatui.Style

  @type throbber_set ::
          :braille
          | :dots
          | :ascii
          | :vertical_block
          | :horizontal_block
          | :arrow
          | :clock
          | :box_drawing
          | :quadrant_block
          | :white_square
          | :white_circle
          | :black_circle

  @type t :: %__MODULE__{
          label: String.t(),
          style: Style.t(),
          throbber_style: Style.t(),
          throbber_set: throbber_set(),
          step: non_neg_integer(),
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct label: "",
            style: %Style{},
            throbber_style: %Style{},
            throbber_set: :braille,
            step: 0,
            block: nil
end
