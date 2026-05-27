defmodule ExRatatui.Property.LayoutPropertyTest do
  @moduledoc """
  Property-based invariants for `ExRatatui.Layout.split/3`.

  Splitting a `Rect` by N constraints should always produce:

    * exactly N sub-rects (when N > 0; empty constraints → empty list),
    * rects that sit within the parent's bounds,
    * rects with non-negative dimensions,
    * no gaps or overlaps along the split axis (children are contiguous),
    * the off-axis dimension/position unchanged from the parent.

  These hold for any mix of `:length`, `:percentage`, `:min`, `:max`, and
  `:ratio` constraints, even when they over- or under-fill the parent.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect

  # Generators -------------------------------------------------------------

  defp rect_gen do
    gen all(
          x <- integer(0..1000),
          y <- integer(0..1000),
          width <- integer(0..500),
          height <- integer(0..500)
        ) do
      %Rect{x: x, y: y, width: width, height: height}
    end
  end

  defp direction_gen, do: member_of([:horizontal, :vertical])

  defp constraint_gen do
    one_of([
      tuple({constant(:length), integer(0..200)}),
      tuple({constant(:percentage), integer(0..100)}),
      tuple({constant(:min), integer(0..100)}),
      tuple({constant(:max), integer(0..100)}),
      tuple({constant(:fill), integer(0..10)}),
      gen all(num <- integer(0..10), den <- integer(1..10)) do
        {:ratio, num, den}
      end
    ])
  end

  defp constraints_gen do
    # At least 1, at most 6 — keeps shrinking tractable.
    list_of(constraint_gen(), min_length: 1, max_length: 6)
  end

  # Properties -------------------------------------------------------------

  property "split returns one rect per constraint" do
    check all(
            parent <- rect_gen(),
            direction <- direction_gen(),
            constraints <- constraints_gen()
          ) do
      rects = Layout.split(parent, direction, constraints)
      assert is_list(rects)
      assert length(rects) == length(constraints)
    end
  end

  property "empty constraints produce an empty list" do
    check all(parent <- rect_gen(), direction <- direction_gen()) do
      assert Layout.split(parent, direction, []) == []
    end
  end

  property "every sub-rect has non-negative dimensions" do
    check all(
            parent <- rect_gen(),
            direction <- direction_gen(),
            constraints <- constraints_gen()
          ) do
      for %Rect{width: w, height: h} <- Layout.split(parent, direction, constraints) do
        assert w >= 0
        assert h >= 0
      end
    end
  end

  property "every sub-rect sits within parent bounds" do
    check all(
            parent <- rect_gen(),
            direction <- direction_gen(),
            constraints <- constraints_gen()
          ) do
      for rect <- Layout.split(parent, direction, constraints) do
        assert rect.x >= parent.x
        assert rect.y >= parent.y
        assert rect.x + rect.width <= parent.x + parent.width
        assert rect.y + rect.height <= parent.y + parent.height
      end
    end
  end

  property "vertical split preserves the x/width of every child" do
    check all(
            parent <- rect_gen(),
            constraints <- constraints_gen()
          ) do
      for rect <- Layout.split(parent, :vertical, constraints) do
        assert rect.x == parent.x
        assert rect.width == parent.width
      end
    end
  end

  property "horizontal split preserves the y/height of every child" do
    check all(
            parent <- rect_gen(),
            constraints <- constraints_gen()
          ) do
      for rect <- Layout.split(parent, :horizontal, constraints) do
        assert rect.y == parent.y
        assert rect.height == parent.height
      end
    end
  end

  property "vertical split produces contiguous rects along y" do
    check all(
            parent <- rect_gen(),
            constraints <- constraints_gen()
          ) do
      rects = Layout.split(parent, :vertical, constraints)

      rects
      |> Enum.zip(tl(rects) ++ [nil])
      |> Enum.each(fn
        {_, nil} -> :ok
        {a, b} -> assert a.y + a.height == b.y
      end)
    end
  end

  property "horizontal split produces contiguous rects along x" do
    check all(
            parent <- rect_gen(),
            constraints <- constraints_gen()
          ) do
      rects = Layout.split(parent, :horizontal, constraints)

      rects
      |> Enum.zip(tl(rects) ++ [nil])
      |> Enum.each(fn
        {_, nil} -> :ok
        {a, b} -> assert a.x + a.width == b.x
      end)
    end
  end

  property "sum of child sizes along split axis never exceeds parent" do
    check all(
            parent <- rect_gen(),
            direction <- direction_gen(),
            constraints <- constraints_gen()
          ) do
      rects = Layout.split(parent, direction, constraints)

      {parent_size, child_sizes} =
        case direction do
          :vertical -> {parent.height, Enum.map(rects, & &1.height)}
          :horizontal -> {parent.width, Enum.map(rects, & &1.width)}
        end

      assert Enum.sum(child_sizes) <= parent_size
    end
  end

  property "first child starts at the parent's origin on the split axis" do
    check all(
            parent <- rect_gen(),
            direction <- direction_gen(),
            constraints <- constraints_gen()
          ) do
      [first | _] = Layout.split(parent, direction, constraints)

      case direction do
        :vertical -> assert first.y == parent.y
        :horizontal -> assert first.x == parent.x
      end
    end
  end
end
