defmodule ExRatatui.Pixels do
  @moduledoc """
  Raw operations on the RGB8 bitmaps that `ExRatatui.CellSession.Region`
  carries.

  A region's `:data` is row-major, three bytes per pixel, no padding. A
  consumer painting those bitmaps onto a real surface sometimes needs the
  pixels in a different arrangement than the one the widget rasterized —
  a panel mounted on its side wants the bitmap turned. Doing that per
  pixel in Elixir costs a consumer about as much again as painting the
  panel in the first place, so it happens here instead, in one pass over
  the buffer.

  The work is bounded: a region's longest side is capped at 1280 px, so
  the largest bitmap in play is a few megabytes.

  ## Rotation

  Rotations are clockwise, and use the same corner mapping a framebuffer
  consumer uses for its screen. For a `width` × `height` source, the
  pixel landing at destination `(px, py)` comes from source:

    * `90` — `(py, height - 1 - px)`, destination is `height` × `width`
    * `180` — `(width - 1 - px, height - 1 - py)`, destination keeps its size
    * `270` — `(width - 1 - py, px)`, destination is `height` × `width`
  """

  @type angle :: 0 | 90 | 180 | 270

  @doc """
  Rotates an RGB8 bitmap clockwise by `angle` degrees.

  Returns the rotated bytes with the dimensions they now describe — at
  `90` and `270` the width and height are swapped. `0` hands back the
  input untouched, without going through the NIF.

  Raises `ArgumentError` when `data` does not hold exactly
  `width * height * 3` bytes, or when `angle` is not one of `0`, `90`,
  `180` or `270`.

  ## Examples

  A two-pixel row, red then blue, turned a quarter clockwise is a
  two-pixel column, red on top. The bytes are unchanged; the shape is not:

      iex> ExRatatui.Pixels.rotate_rgb8(<<255, 0, 0, 0, 0, 255>>, 2, 1, 90)
      {<<255, 0, 0, 0, 0, 255>>, 1, 2}

  Half a turn keeps the shape and reverses the pixels:

      iex> ExRatatui.Pixels.rotate_rgb8(<<255, 0, 0, 0, 0, 255>>, 2, 1, 180)
      {<<0, 0, 255, 255, 0, 0>>, 2, 1}

  No turn is the identity:

      iex> ExRatatui.Pixels.rotate_rgb8(<<1, 2, 3>>, 1, 1, 0)
      {<<1, 2, 3>>, 1, 1}
  """
  @spec rotate_rgb8(binary(), non_neg_integer(), non_neg_integer(), angle()) ::
          {binary(), non_neg_integer(), non_neg_integer()}
  def rotate_rgb8(data, width, height, 0) when is_binary(data), do: {data, width, height}

  def rotate_rgb8(data, width, height, angle) when is_binary(data) do
    case ExRatatui.Native.rotate_rgb8(width, height, angle, data) do
      {rotated, rotated_width, rotated_height} when is_binary(rotated) ->
        {rotated, rotated_width, rotated_height}

      {:error, reason} ->
        raise ArgumentError,
              "cannot rotate a #{width}x#{height} bitmap from #{byte_size(data)} bytes " <>
                "by #{inspect(angle)}: #{inspect(reason)}"
    end
  end
end
