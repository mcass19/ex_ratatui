defmodule ExRatatui.PixelsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Bitwise

  alias ExRatatui.Pixels

  doctest ExRatatui.Pixels

  # The obvious, slow rotation, straight from the corner mapping. Every
  # assertion below goes against this rather than against a symmetric
  # fixture, because a rotation that is off by a transpose still looks
  # like a rotated picture. The consumer side keeps the same reference —
  # raster_ex_ratatui's Test.Rotation.rotate_frame/5.
  defp reference_rotate(data, _width, _height, 0), do: data

  defp reference_rotate(data, width, height, angle) when angle in [90, 180, 270] do
    {out_width, out_height} = if angle == 180, do: {width, height}, else: {height, width}

    for py <- 0..(out_height - 1), px <- 0..(out_width - 1), into: <<>> do
      {x, y} = source(angle, px, py, width, height)
      binary_part(data, (y * width + x) * 3, 3)
    end
  end

  defp source(90, px, py, _width, height), do: {py, height - 1 - px}
  defp source(180, px, py, width, height), do: {width - 1 - px, height - 1 - py}
  defp source(270, px, py, width, _height), do: {width - 1 - py, px}

  # A width × height bitmap where every pixel is distinct.
  defp bitmap(width, height) do
    for i <- 0..(width * height - 1), into: <<>>, do: <<i * 10 + 1, i * 10 + 2, i * 10 + 3>>
  end

  describe "rotate_rgb8/4" do
    test "matches the reference rotation on a non-square bitmap" do
      data = bitmap(3, 2)

      for angle <- [90, 180, 270] do
        expected_dims = if angle == 180, do: {3, 2}, else: {2, 3}

        assert {rotated, width, height} = Pixels.rotate_rgb8(data, 3, 2, angle)
        assert {width, height} == expected_dims, "dimensions at #{angle}"
        assert rotated == reference_rotate(data, 3, 2, angle), "bytes at #{angle}"
      end
    end

    test "matches the reference on single-row and single-column bitmaps" do
      for {width, height} <- [{4, 1}, {1, 4}], angle <- [90, 180, 270] do
        data = bitmap(width, height)

        assert {rotated, _, _} = Pixels.rotate_rgb8(data, width, height, angle)

        assert rotated == reference_rotate(data, width, height, angle),
               "#{width}x#{height} at #{angle}"
      end
    end

    test "four quarter turns are the identity" do
      data = bitmap(3, 2)

      assert Enum.reduce(1..4, {data, 3, 2}, fn _, {current, width, height} ->
               Pixels.rotate_rgb8(current, width, height, 90)
             end) == {data, 3, 2}
    end

    test "0 returns the bitmap untouched" do
      data = bitmap(3, 2)
      assert Pixels.rotate_rgb8(data, 3, 2, 0) == {data, 3, 2}
    end

    test "an empty bitmap comes back empty with swapped dimensions" do
      assert Pixels.rotate_rgb8(<<>>, 0, 4, 90) == {<<>>, 4, 0}
    end

    test "raises on a byte count that is not three per pixel" do
      assert_raise ArgumentError, ~r/cannot rotate a 2x2 bitmap from 11 bytes/, fn ->
        Pixels.rotate_rgb8(<<0::size(11)-unit(8)>>, 2, 2, 90)
      end
    end

    test "raises on an unsupported angle" do
      assert_raise ArgumentError, ~r/by 45: :invalid_angle/, fn ->
        Pixels.rotate_rgb8(bitmap(2, 2), 2, 2, 45)
      end
    end
  end

  # The packing contract, step by step: sample the clipped logical image
  # against the full scale, turn it with the rotation reference above, then
  # pack every pixel at its panel position.
  @bayer {{0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5}}

  defp reference_pack(_data, _width, _height, _format, opts)
       when elem(opts.clip, 0) == 0 or elem(opts.clip, 1) == 0,
       do: <<>>

  defp reference_pack(data, width, height, format, opts) do
    %{scale_to: {scale_w, scale_h}, clip: {clip_w, clip_h}, rotate: angle, origin: {ox, oy}} =
      opts

    logical =
      for ly <- 0..(clip_h - 1), lx <- 0..(clip_w - 1), into: <<>> do
        {x, y} = {div(lx * width, scale_w), div(ly * height, scale_h)}
        binary_part(data, (y * width + x) * 3, 3)
      end

    out_width = if angle in [90, 270], do: clip_h, else: clip_w
    rotated = reference_rotate(logical, clip_w, clip_h, angle)

    for {<<r, g, b>>, i} <- Enum.with_index(for(<<pixel::binary-3 <- rotated>>, do: pixel)),
        into: <<>> do
      reference_pixel(format, r, g, b, ox + rem(i, out_width), oy + div(i, out_width))
    end
  end

  defp reference_pixel(:rgb8, r, g, b, _x, _y), do: <<r, g, b>>

  defp reference_pixel(:rgb565, r, g, b, _x, _y),
    do: <<(r >>> 3) <<< 11 ||| (g >>> 2) <<< 5 ||| b >>> 3::little-16>>

  defp reference_pixel(:xrgb8888, r, g, b, _x, _y), do: <<b, g, r, 255>>

  defp reference_pixel(:mono_bayer4, r, g, b, x, y) do
    luma = div(299 * r + 587 * g + 114 * b, 1000)
    threshold = @bayer |> elem(rem(y, 4)) |> elem(rem(x, 4)) |> Kernel.*(16) |> Kernel.+(8)
    if luma < threshold, do: <<0>>, else: <<255>>
  end

  defp pack_case do
    gen all(
          width <- integer(1..40),
          height <- integer(1..40),
          data <- binary(length: width * height * 3),
          scale_w <- integer(max(div(width, 4), 1)..(width * 4)),
          scale_h <- integer(max(div(height, 4), 1)..(height * 4)),
          clip_w <- integer(0..scale_w),
          clip_h <- integer(0..scale_h),
          rotate <- member_of([0, 90, 180, 270]),
          format <- member_of([:rgb8, :rgb565, :xrgb8888, :mono_bayer4]),
          origin <- {integer(0..7), integer(0..7)}
        ) do
      opts = %{
        scale_to: {scale_w, scale_h},
        clip: {clip_w, clip_h},
        rotate: rotate,
        origin: origin
      }

      {data, width, height, format, opts}
    end
  end

  describe "pack_rgb8/5" do
    property "matches the reference over random bitmaps, scales, clips, angles and formats" do
      check all({data, width, height, format, opts} <- pack_case(), max_runs: 300) do
        {clip_w, clip_h} = opts.clip
        expected_dims = if opts.rotate in [90, 270], do: {clip_h, clip_w}, else: {clip_w, clip_h}

        assert {packed, out_width, out_height} =
                 Pixels.pack_rgb8(data, width, height, format, Map.to_list(opts))

        assert {out_width, out_height} == expected_dims
        assert packed == reference_pack(data, width, height, format, opts)
      end
    end

    test "matches the rotation reference for :rgb8 with only a turn" do
      data = bitmap(3, 2)

      for angle <- [90, 180, 270] do
        assert {rotated, _, _} = Pixels.pack_rgb8(data, 3, 2, :rgb8, rotate: angle)
        assert rotated == reference_rotate(data, 3, 2, angle)
      end
    end

    test ":rgb8 with the defaults returns the input" do
      data = bitmap(3, 2)
      assert Pixels.pack_rgb8(data, 3, 2, :rgb8) == {data, 3, 2}
    end

    test ":mono_bayer4 dithers a mid grey into a checkerboard anchored at the origin" do
      grey = :binary.copy(<<128>>, 4 * 4 * 3)
      row = <<255, 0, 255, 0>>
      shifted = <<0, 255, 0, 255>>

      assert {packed, 4, 4} = Pixels.pack_rgb8(grey, 4, 4, :mono_bayer4)
      assert packed == row <> shifted <> row <> shifted

      assert {packed, 4, 4} = Pixels.pack_rgb8(grey, 4, 4, :mono_bayer4, origin: {1, 0})
      assert packed == shifted <> row <> shifted <> row
    end

    test "an empty clip returns no bytes" do
      assert Pixels.pack_rgb8(bitmap(2, 2), 2, 2, :rgb565, clip: {0, 2}, rotate: 90) ==
               {<<>>, 2, 0}
    end

    test "raises on an unknown format" do
      # Opaque at compile time, so the type checker lets the bad format through.
      Process.put(:pixels_test_bad_format, :rgb555)
      bad = Process.get(:pixels_test_bad_format)

      assert_raise ArgumentError, ~r/unknown pixel format :rgb555/, fn ->
        Pixels.pack_rgb8(bitmap(1, 1), 1, 1, bad)
      end
    end

    test "raises on an unknown option" do
      assert_raise ArgumentError, ~r/unknown keys \[:size\]/, fn ->
        Pixels.pack_rgb8(bitmap(1, 1), 1, 1, :rgb8, size: {2, 2})
      end
    end

    test "raises on malformed tuples, naming the option" do
      for {key, value} <- [scale_to: {2}, clip: {-1, 1}, origin: "0,0", scale_to: {1.0, 1}] do
        assert_raise ArgumentError, ~r/expected #{inspect(key)} to be a tuple/, fn ->
          Pixels.pack_rgb8(bitmap(1, 1), 1, 1, :rgb8, [{key, value}])
        end
      end
    end

    test "raises on an unsupported angle" do
      assert_raise ArgumentError,
                   ~r/expected :rotate to be one of \[0, 90, 180, 270\], got: 45/,
                   fn ->
                     Pixels.pack_rgb8(bitmap(1, 1), 1, 1, :rgb8, rotate: 45)
                   end
    end

    test "raises on a byte count that is not three per pixel" do
      assert_raise ArgumentError,
                   ~r/cannot pack a 2x2 bitmap from 11 bytes as :rgb565.*: :invalid_dimensions/,
                   fn -> Pixels.pack_rgb8(<<0::size(11)-unit(8)>>, 2, 2, :rgb565) end
    end

    test "raises on a clip larger than the scale" do
      assert_raise ArgumentError, ~r/:invalid_clip/, fn ->
        Pixels.pack_rgb8(bitmap(2, 2), 2, 2, :rgb8, clip: {3, 2})
      end
    end

    test "raises on kept pixels without a source" do
      assert_raise ArgumentError, ~r/:invalid_dimensions/, fn ->
        Pixels.pack_rgb8(<<>>, 0, 2, :rgb8, scale_to: {2, 2})
      end
    end
  end
end
