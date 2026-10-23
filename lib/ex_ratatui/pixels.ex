defmodule ExRatatui.Pixels do
  @moduledoc """
  Raw operations on the RGB8 bitmaps that `ExRatatui.CellSession.Region`
  carries.

  A region's `:data` is row-major, three bytes per pixel, no padding. A
  consumer painting those bitmaps onto a real surface sometimes needs the
  pixels in a different arrangement than the one the widget rasterized —
  a panel mounted on its side wants the bitmap turned, a framebuffer wants
  it scaled to the rect and packed into its own pixel format. Doing that
  per pixel in Elixir costs a consumer about as much again as painting the
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

  ## Packing

  `pack_rgb8/5` takes a region's bitmap all the way to the bytes a panel stores, in a single pass with no intermediate copies:

    1. **Sample** onto `:scale_to` (the rect's pixel size in the app's orientation) by floor nearest: logical pixel `(lx, ly)` is source `(div(lx * width, scale_w), div(ly * height, scale_h))`.
    2. **Clip** to the top-left `:clip` part of that. Sampling is against the full `:scale_to`, so a region cut off at the edge of the grid samples as if it were whole.
    3. **Rotate** clockwise by `:rotate`, with the corner mapping above.
    4. **Pack** each pixel:

  | Format | Bytes per pixel | Layout |
  |---|---|---|
  | `:rgb8` | 3 | `r, g, b` (no packing) |
  | `:rgb565` | 2 | `rrrrrggg gggbbbbb`, little-endian |
  | `:xrgb8888` | 4 | `b, g, r, 255` |
  | `:mono_bayer4` | 1 | `0` (ink) or `255` (paper) |

  `:mono_bayer4` compares Rec. 601 luma `div(299 * r + 587 * g + 114 * b, 1000)` against a Bayer 4×4 threshold, `bayer[rem(y, 4)][rem(x, 4)] * 16 + 8` with `bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]`. `x` and `y` are panel positions: `:origin` is where the output's top-left pixel lands, so the dither pattern stays fixed to the panel wherever a region sits.

  `:rgb8` is there for consumers with formats of their own: they still get the sampling, clipping and rotation natively and pack the result themselves.

  A pass costs one or two nanoseconds a pixel on a laptop, the same flat or turned; packing per pixel in Elixir is closer to 20–30.
  """

  @type angle :: 0 | 90 | 180 | 270

  @typedoc "A packed pixel layout; see the Packing section above."
  @type format :: :rgb8 | :rgb565 | :xrgb8888 | :mono_bayer4

  @typedoc """
  Options for `pack_rgb8/5`:

    * `:scale_to` — `{width, height}` the bitmap is resampled to, before rotation. Defaults to the source size
    * `:clip` — `{width, height}` of the top-left part of the resampled image that is kept. Defaults to `:scale_to`
    * `:rotate` — clockwise turn, `0`, `90`, `180` or `270`. Defaults to `0`
    * `:origin` — `{x, y}` panel position of the output's top-left pixel, used by the `:mono_bayer4` dither. Defaults to `{0, 0}`
  """
  @type pack_opts :: [
          scale_to: {non_neg_integer(), non_neg_integer()},
          clip: {non_neg_integer(), non_neg_integer()},
          rotate: angle(),
          origin: {non_neg_integer(), non_neg_integer()}
        ]

  @formats [:rgb8, :rgb565, :xrgb8888, :mono_bayer4]
  @angles [0, 90, 180, 270]

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

  @doc """
  Resamples, clips, rotates and packs an RGB8 bitmap in one pass.

  Returns the packed bytes with the output's width and height: the `:clip` size, swapped at `90` and `270`. See the Packing section of the moduledoc for each step and the byte layout of every `format`, and `t:pack_opts/0` for the options.

  Raises `ArgumentError` on an unknown format or option, a malformed option value, `data` that does not hold exactly `width * height * 3` bytes, or a `:clip` larger than `:scale_to`.

  ## Examples

  Red then blue, as RGB565 and as XRGB8888:

      iex> ExRatatui.Pixels.pack_rgb8(<<255, 0, 0, 0, 0, 255>>, 2, 1, :rgb565)
      {<<0, 248, 31, 0>>, 2, 1}

      iex> ExRatatui.Pixels.pack_rgb8(<<255, 0, 0, 0, 0, 255>>, 2, 1, :xrgb8888)
      {<<0, 0, 255, 255, 255, 0, 0, 255>>, 2, 1}

  Turned a quarter clockwise, the row becomes a column, red on top:

      iex> ExRatatui.Pixels.pack_rgb8(<<255, 0, 0, 0, 0, 255>>, 2, 1, :rgb8, rotate: 90)
      {<<255, 0, 0, 0, 0, 255>>, 1, 2}

  One pixel scaled up to a 2×2 rect repeats it:

      iex> ExRatatui.Pixels.pack_rgb8(<<9, 8, 7>>, 1, 1, :rgb8, scale_to: {2, 2})
      {<<9, 8, 7, 9, 8, 7, 9, 8, 7, 9, 8, 7>>, 2, 2}
  """
  @spec pack_rgb8(binary(), non_neg_integer(), non_neg_integer(), format(), pack_opts()) ::
          {binary(), non_neg_integer(), non_neg_integer()}
  def pack_rgb8(data, width, height, format, opts \\ []) when is_binary(data) do
    if format not in @formats do
      raise ArgumentError,
            "unknown pixel format #{inspect(format)}, expected one of #{inspect(@formats)}"
    end

    opts =
      Keyword.validate!(opts, scale_to: {width, height}, clip: nil, rotate: 0, origin: {0, 0})

    scale_to = pair!(opts, :scale_to)

    native_opts = %{
      format: format,
      scale_to: scale_to,
      clip: if(opts[:clip], do: pair!(opts, :clip), else: scale_to),
      rotate: angle!(opts[:rotate]),
      origin: pair!(opts, :origin)
    }

    case ExRatatui.Native.pack_rgb8(width, height, data, native_opts) do
      {packed, packed_width, packed_height} when is_binary(packed) ->
        {packed, packed_width, packed_height}

      {:error, reason} ->
        raise ArgumentError,
              "cannot pack a #{width}x#{height} bitmap from #{byte_size(data)} bytes " <>
                "as #{inspect(format)} with #{inspect(Map.delete(native_opts, :format))}: " <>
                inspect(reason)
    end
  end

  defp pair!(opts, key) do
    case Keyword.fetch!(opts, key) do
      {a, b} = pair when is_integer(a) and a >= 0 and is_integer(b) and b >= 0 ->
        pair

      other ->
        raise ArgumentError,
              "expected #{inspect(key)} to be a tuple of two non-negative integers, " <>
                "got: #{inspect(other)}"
    end
  end

  defp angle!(angle) when angle in @angles, do: angle

  defp angle!(angle) do
    raise ArgumentError,
          "expected :rotate to be one of #{inspect(@angles)}, got: #{inspect(angle)}"
  end
end
