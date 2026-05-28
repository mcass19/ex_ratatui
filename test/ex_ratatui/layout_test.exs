defmodule ExRatatui.LayoutTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.Layout
  doctest ExRatatui.Layout.Rect

  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect

  describe "split/3" do
    test "vertical split with percentages" do
      area = %Rect{x: 0, y: 0, width: 80, height: 24}
      [top, bottom] = Layout.split(area, :vertical, [{:percentage, 50}, {:percentage, 50}])

      assert %Rect{x: 0, y: 0, width: 80, height: 12} = top
      assert %Rect{x: 0, y: 12, width: 80, height: 12} = bottom
    end

    test "horizontal split with percentages" do
      area = %Rect{x: 0, y: 0, width: 80, height: 24}
      [left, right] = Layout.split(area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

      assert %Rect{x: 0, y: 0, width: 40, height: 24} = left
      assert %Rect{x: 40, y: 0, width: 40, height: 24} = right
    end

    test "vertical split with length and min" do
      area = %Rect{x: 0, y: 0, width: 80, height: 24}
      [header, body] = Layout.split(area, :vertical, [{:length, 3}, {:min, 0}])

      assert header.height == 3
      assert body.y == 3
      assert body.height == 21
    end

    test "three-way vertical split" do
      area = %Rect{x: 0, y: 0, width: 60, height: 30}

      [header, body, footer] =
        Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 1}])

      assert %Rect{x: 0, y: 0, width: 60, height: 3} = header
      assert %Rect{x: 0, y: 3, width: 60, height: 26} = body
      assert %Rect{x: 0, y: 29, width: 60, height: 1} = footer
    end

    test "split with offset area" do
      area = %Rect{x: 5, y: 5, width: 40, height: 20}
      [left, right] = Layout.split(area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

      assert %Rect{x: 5, y: 5, width: 20, height: 20} = left
      assert %Rect{x: 25, y: 5, width: 20, height: 20} = right
    end

    test "ratio constraint" do
      area = %Rect{x: 0, y: 0, width: 90, height: 24}
      [left, right] = Layout.split(area, :horizontal, [{:ratio, 1, 3}, {:ratio, 2, 3}])

      assert left.width == 30
      assert right.width == 60
    end

    test "max constraint" do
      area = %Rect{x: 0, y: 0, width: 80, height: 24}
      [top, bottom] = Layout.split(area, :vertical, [{:max, 5}, {:min, 0}])

      assert top.height == 5
      assert bottom.height == 19
    end

    test "returns Rect structs" do
      area = %Rect{x: 0, y: 0, width: 80, height: 24}
      results = Layout.split(area, :vertical, [{:percentage, 100}])

      assert [%Rect{}] = results
    end

    test "single constraint returns single rect" do
      area = %Rect{x: 0, y: 0, width: 80, height: 24}
      [rect] = Layout.split(area, :vertical, [{:percentage, 100}])

      assert rect == area
    end

    test "returns error for invalid constraints" do
      area = %Rect{x: 0, y: 0, width: 80, height: 24}
      assert {:error, _reason} = Layout.split(area, :vertical, [{:ratio, 1, 0}])
    end
  end

  describe "split/4 with :fill constraints" do
    test "distributes remaining space by weight" do
      area = %Rect{x: 0, y: 0, width: 60, height: 1}
      [a, b, c] = Layout.split(area, :horizontal, [{:fill, 1}, {:fill, 2}, {:fill, 3}])

      assert a.width + b.width + c.width == 60
      assert a.width < b.width
      assert b.width < c.width
    end

    test "fill yields remaining space after Length is satisfied" do
      area = %Rect{x: 0, y: 0, width: 50, height: 1}
      [fixed, growable] = Layout.split(area, :horizontal, [{:length, 10}, {:fill, 1}])

      assert fixed.width == 10
      assert growable.width == 40
    end
  end

  describe "split/4 with :flex" do
    test ":center pushes a fixed-length segment to the middle of the area" do
      area = %Rect{x: 0, y: 0, width: 30, height: 1}
      [popup] = Layout.split(area, :horizontal, [{:length, 10}], flex: :center)

      assert popup.x == 10
      assert popup.width == 10
    end

    test ":end packs segments toward the end of the area" do
      area = %Rect{x: 0, y: 0, width: 30, height: 1}
      [seg] = Layout.split(area, :horizontal, [{:length, 5}], flex: :end)

      assert seg.x == 25
      assert seg.width == 5
    end

    test ":space_between distributes extra space between segments" do
      area = %Rect{x: 0, y: 0, width: 30, height: 1}
      [a, b] = Layout.split(area, :horizontal, [{:length, 5}, {:length, 5}], flex: :space_between)

      assert a.x == 0
      assert b.x == 25
    end

    test "raises on unknown :flex atom" do
      area = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert_raise ArgumentError, ~r/:flex expected one of/, fn ->
        Layout.split(area, :horizontal, [{:length, 5}], flex: :diagonal)
      end
    end
  end

  describe "split/4 with :spacing" do
    test "inserts a gap between adjacent segments" do
      area = %Rect{x: 0, y: 0, width: 22, height: 1}

      [a, b] =
        Layout.split(area, :horizontal, [{:length, 10}, {:length, 10}], spacing: 2)

      assert a.x == 0
      assert a.width == 10
      assert b.x == 12
      assert b.width == 10
    end

    test "raises on non-integer or negative :spacing" do
      area = %Rect{x: 0, y: 0, width: 22, height: 1}

      assert_raise ArgumentError, ~r/:spacing expected a non-negative integer/, fn ->
        Layout.split(area, :horizontal, [{:length, 10}], spacing: -1)
      end

      assert_raise ArgumentError, ~r/:spacing expected a non-negative integer/, fn ->
        Layout.split(area, :horizontal, [{:length, 10}], spacing: 1.5)
      end
    end
  end

  describe "split/4 with :margin" do
    test "uniform :margin insets all four sides before splitting" do
      area = %Rect{x: 0, y: 0, width: 20, height: 10}
      [body] = Layout.split(area, :vertical, [{:min, 0}], margin: 1)

      assert body == %Rect{x: 1, y: 1, width: 18, height: 8}
    end

    test ":horizontal_margin and :vertical_margin inset per-axis" do
      area = %Rect{x: 0, y: 0, width: 20, height: 10}

      [body] =
        Layout.split(area, :vertical, [{:min, 0}], horizontal_margin: 3, vertical_margin: 1)

      assert body == %Rect{x: 3, y: 1, width: 14, height: 8}
    end

    test "per-axis margin overrides uniform :margin for that axis" do
      area = %Rect{x: 0, y: 0, width: 20, height: 10}

      [body] = Layout.split(area, :vertical, [{:min, 0}], margin: 2, vertical_margin: 0)

      assert body == %Rect{x: 2, y: 0, width: 16, height: 10}
    end

    test "raises on negative or non-integer margin" do
      area = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/:margin expected a non-negative integer/, fn ->
        Layout.split(area, :vertical, [{:min, 0}], margin: -1)
      end

      assert_raise ArgumentError, ~r/:horizontal_margin expected a non-negative integer/, fn ->
        Layout.split(area, :vertical, [{:min, 0}], horizontal_margin: 1.5)
      end
    end
  end
end
