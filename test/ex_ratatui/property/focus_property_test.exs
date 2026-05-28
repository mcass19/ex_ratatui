defmodule ExRatatui.Property.FocusPropertyTest do
  @moduledoc """
  Property-based invariants for `ExRatatui.Focus`.

  `Focus` is a ring over an ordered, unique list of atom IDs. The core
  invariants are:

    * `current/1` always returns an ID that was registered.
    * `next` and `prev` are inverses.
    * N applications of `next` on a ring of length N returns to the origin.
    * `handle_key/2` with a next/prev key is equivalent to `next/1` or `prev/1`
      and consumes the event; any other key passes through unchanged.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.Event
  alias ExRatatui.Focus
  alias ExRatatui.Layout.Rect

  # Generators -------------------------------------------------------------

  # Small, closed alphabet — keeps uniqueness easy and shrink useful.
  @alphabet ~w(a b c d e f g h)a

  defp ids_gen do
    gen all(
          size <- integer(1..length(@alphabet)),
          picks <-
            @alphabet
            |> Enum.take(length(@alphabet))
            |> Enum.shuffle()
            |> Enum.take(size)
            |> constant()
        ) do
      picks
    end
  end

  defp focus_gen do
    gen all(ids <- ids_gen()) do
      Focus.new(ids)
    end
  end

  # Properties -------------------------------------------------------------

  property "current/1 is always a registered ID" do
    check all(focus <- focus_gen()) do
      assert Focus.current(focus) in focus.ids
    end
  end

  property "next ∘ prev == identity" do
    check all(focus <- focus_gen()) do
      assert focus |> Focus.next() |> Focus.prev() == focus
      assert focus |> Focus.prev() |> Focus.next() == focus
    end
  end

  property "N applications of next cycle back to start" do
    check all(focus <- focus_gen()) do
      n = length(focus.ids)
      cycled = Enum.reduce(1..n, focus, fn _, f -> Focus.next(f) end)
      assert cycled == focus
    end
  end

  property "N applications of prev cycle back to start" do
    check all(focus <- focus_gen()) do
      n = length(focus.ids)
      cycled = Enum.reduce(1..n, focus, fn _, f -> Focus.prev(f) end)
      assert cycled == focus
    end
  end

  property "focus/2 to any registered ID makes it current" do
    check all(focus <- focus_gen(), chosen <- member_of(focus.ids)) do
      assert Focus.focused?(Focus.focus(focus, chosen), chosen)
    end
  end

  property "arbitrary next/prev sequence keeps current inside the ring" do
    check all(
            focus <- focus_gen(),
            steps <- list_of(member_of([:next, :prev]), max_length: 20)
          ) do
      final =
        Enum.reduce(steps, focus, fn
          :next, f -> Focus.next(f)
          :prev, f -> Focus.prev(f)
        end)

      assert Focus.current(final) in focus.ids
    end
  end

  property "handle_key with default Tab advances focus and consumes event" do
    check all(focus <- focus_gen()) do
      event = %Event.Key{code: "tab", modifiers: [], kind: :press}
      assert {moved, nil} = Focus.handle_key(focus, event)
      assert moved == Focus.next(focus)
    end
  end

  property "handle_key with default Shift+Tab retreats focus" do
    check all(focus <- focus_gen()) do
      event = %Event.Key{code: "tab", modifiers: ["shift"], kind: :press}
      assert {moved, nil} = Focus.handle_key(focus, event)
      assert moved == Focus.prev(focus)
    end
  end

  property "handle_key with back_tab also retreats focus" do
    check all(focus <- focus_gen()) do
      event = %Event.Key{code: "back_tab", modifiers: [], kind: :press}
      assert {moved, nil} = Focus.handle_key(focus, event)
      assert moved == Focus.prev(focus)
    end
  end

  property "handle_key with unrelated key passes through unchanged" do
    check all(
            focus <- focus_gen(),
            code <- member_of(~w(enter esc left right up down a b 1 space))
          ) do
      event = %Event.Key{code: code, modifiers: [], kind: :press}
      assert {^focus, ^event} = Focus.handle_key(focus, event)
    end
  end

  property "custom next_keys match regardless of modifier order" do
    check all(focus <- focus_gen()) do
      focus =
        Focus.new(focus.ids,
          next_keys: [%Event.Key{code: "right", modifiers: ["ctrl", "shift"]}]
        )

      # Same modifier set, reversed order — should still match.
      event = %Event.Key{code: "right", modifiers: ["shift", "ctrl"], kind: :press}
      assert {moved, nil} = Focus.handle_key(focus, event)
      assert moved == Focus.next(focus)
    end
  end

  # Mouse routing ----------------------------------------------------------

  defp rect_gen do
    gen all(
          x <- integer(0..100),
          y <- integer(0..40),
          w <- integer(1..40),
          h <- integer(1..20)
        ) do
      %Rect{x: x, y: y, width: w, height: h}
    end
  end

  defp focus_with_regions_gen do
    gen all(
          focus <- focus_gen(),
          rects <- list_of(rect_gen(), length: length(focus.ids))
        ) do
      regions = focus.ids |> Enum.zip(rects) |> Map.new()
      Focus.set_regions(focus, regions)
    end
  end

  property "set_region/3 round-trips: region/2 returns what was set" do
    check all(focus <- focus_gen(), rect <- rect_gen()) do
      id = Enum.random(focus.ids)
      updated = Focus.set_region(focus, id, rect)
      assert Focus.region(updated, id) == rect
    end
  end

  property "set_regions/2 stores every entry; region/2 returns each rect" do
    check all(focus <- focus_with_regions_gen()) do
      Enum.each(focus.ids, fn id ->
        rect = Focus.region(focus, id)
        assert %Rect{} = rect
      end)
    end
  end

  property "set_region/3 raises on unknown id" do
    check all(focus <- focus_gen(), rect <- rect_gen()) do
      unknown = :"not_in_ring_#{System.unique_integer([:positive])}"

      assert_raise ArgumentError, ~r/not found in focus ring/, fn ->
        Focus.set_region(focus, unknown, rect)
      end
    end
  end

  property "at/3 inside a region returns that id (or a smaller overlapping one)" do
    check all(focus <- focus_with_regions_gen()) do
      id = Enum.random(focus.ids)
      %Rect{x: rx, y: ry, width: w, height: h} = Focus.region(focus, id)

      # A point definitively inside the region (any cell in its area).
      cx = rx + div(w, 2)
      cy = ry + div(h, 2)

      hit = Focus.at(focus, cx, cy)
      assert hit != nil

      # The returned id's region must contain the point AND have area
      # <= the picked id's region (Focus.at picks smallest on overlap).
      hit_rect = Focus.region(focus, hit)
      assert hit_rect.width * hit_rect.height <= w * h
      assert cx >= hit_rect.x and cx < hit_rect.x + hit_rect.width
      assert cy >= hit_rect.y and cy < hit_rect.y + hit_rect.height
    end
  end

  property "at/3 well outside every region returns nil" do
    check all(focus <- focus_with_regions_gen()) do
      # Push way past every registered rect.
      max_x =
        focus.regions
        |> Map.values()
        |> Enum.map(fn r -> r.x + r.width end)
        |> Enum.max(fn -> 0 end)

      max_y =
        focus.regions
        |> Map.values()
        |> Enum.map(fn r -> r.y + r.height end)
        |> Enum.max(fn -> 0 end)

      assert Focus.at(focus, max_x + 1000, max_y + 1000) == nil
    end
  end

  property "handle_mouse left-down inside a region focuses that id; event passes through" do
    check all(focus <- focus_with_regions_gen()) do
      id = Enum.random(focus.ids)
      %Rect{x: rx, y: ry, width: w, height: h} = Focus.region(focus, id)
      cx = rx + div(w, 2)
      cy = ry + div(h, 2)

      event = %Event.Mouse{kind: "down", button: "left", x: cx, y: cy, modifiers: []}
      assert {moved, ^event} = Focus.handle_mouse(focus, event)
      assert moved.regions == focus.regions

      # The focused id must now contain the click point. (May not equal
      # `id` if a smaller overlapping region wins — Focus.at picks the
      # smallest by area on overlap.)
      hit_rect = Focus.region(moved, Focus.current(moved))
      assert cx >= hit_rect.x and cx < hit_rect.x + hit_rect.width
      assert cy >= hit_rect.y and cy < hit_rect.y + hit_rect.height
    end
  end

  property "handle_mouse non-left or non-down is identity on focus; event passes through" do
    check all(
            focus <- focus_with_regions_gen(),
            kind <- member_of(~w(up drag moved scroll_up scroll_down scroll_left scroll_right)),
            button <- member_of(~w(left right middle)),
            x <- integer(0..200),
            y <- integer(0..100)
          ) do
      event = %Event.Mouse{kind: kind, button: button, x: x, y: y, modifiers: []}
      assert {^focus, ^event} = Focus.handle_mouse(focus, event)
    end
  end

  property "handle_mouse left-down outside every region leaves focus untouched" do
    check all(focus <- focus_with_regions_gen()) do
      # A point well past every region's bottom-right corner.
      px =
        focus.regions
        |> Map.values()
        |> Enum.map(&(&1.x + &1.width))
        |> Enum.max()
        |> Kernel.+(50)

      py =
        focus.regions
        |> Map.values()
        |> Enum.map(&(&1.y + &1.height))
        |> Enum.max()
        |> Kernel.+(50)

      event = %Event.Mouse{kind: "down", button: "left", x: px, y: py, modifiers: []}
      assert {^focus, ^event} = Focus.handle_mouse(focus, event)
    end
  end
end
