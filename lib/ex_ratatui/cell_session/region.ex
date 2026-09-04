defmodule ExRatatui.CellSession.Region do
  @moduledoc """
  A bitmap that a pixel-mode widget handed to an `ExRatatui.CellSession`
  created with a `:font_size`, covering a rect of cells.

  Terminal graphics protocols smuggle their bytes through one cell's
  symbol, which a cell diff cannot carry. A surface with real pixels does
  not need the escape at all: it wants the bitmap and the rect it covers.
  So on a session that knows its cell pixel size, `ExRatatui.Widgets.Viewport3D`
  and `ExRatatui.Widgets.Image` in a pixel mode rasterize into a region,
  and the cells they cover arrive as plain blank cells.

  ## Fields

    * `:x`, `:y`, `:width`, `:height` — the covered rect, in cells
    * `:pixel_width`, `:pixel_height` — the bitmap's size in pixels.
      Usually `width * font_width` by `height * font_height`; the longest
      side is capped (1280 px), so a very large rect gets a smaller
      bitmap to scale up
    * `:format` — `:rgb8`: row-major, three bytes per pixel, no padding
    * `:data` — the pixel bytes, `pixel_width * pixel_height * 3` long

  ## Contract

  `ExRatatui.CellSession.Snapshot` and `ExRatatui.CellSession.Diff` carry the
  **complete** list of regions on screen for that frame, never a delta. A
  region that is not listed is gone. Paint the cells first, then blit every
  region over its rect, scaling if the bitmap is smaller than the rect.

  ## Examples

      iex> ExRatatui.CellSession.Region.from_native(%{
      ...>   x: 2, y: 1, width: 2, height: 1,
      ...>   pixel_width: 2, pixel_height: 1, format: :rgb8,
      ...>   data: <<255, 0, 0, 0, 0, 255>>
      ...> })
      %ExRatatui.CellSession.Region{
        x: 2, y: 1, width: 2, height: 1,
        pixel_width: 2, pixel_height: 1, format: :rgb8,
        data: <<255, 0, 0, 0, 0, 255>>
      }
  """

  defstruct x: 0,
            y: 0,
            width: 0,
            height: 0,
            pixel_width: 0,
            pixel_height: 0,
            format: :rgb8,
            data: <<>>

  @type t :: %__MODULE__{
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          pixel_width: non_neg_integer(),
          pixel_height: non_neg_integer(),
          format: :rgb8,
          data: binary()
        }

  @doc """
  Builds a `t:t/0` from the raw map the NIF returns for one region.
  """
  @spec from_native(map()) :: t()
  def from_native(%{
        x: x,
        y: y,
        width: width,
        height: height,
        pixel_width: pixel_width,
        pixel_height: pixel_height,
        format: format,
        data: data
      }) do
    %__MODULE__{
      x: x,
      y: y,
      width: width,
      height: height,
      pixel_width: pixel_width,
      pixel_height: pixel_height,
      format: format,
      data: data
    }
  end
end
