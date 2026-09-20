defmodule ExRatatui.PixelsTest do
  use ExUnit.Case, async: true

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
end
