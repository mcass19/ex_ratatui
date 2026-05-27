defmodule ExRatatui.FocusTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.Focus

  alias ExRatatui.Event
  alias ExRatatui.Focus
  alias ExRatatui.Layout.Rect

  describe "new/2" do
    test "defaults :initial to the head of the ring" do
      focus = Focus.new([:a, :b, :c])
      assert Focus.current(focus) == :a
    end

    test "honors :initial" do
      focus = Focus.new([:a, :b, :c], initial: :c)
      assert Focus.current(focus) == :c
    end

    test "stores default next/prev keys" do
      focus = Focus.new([:a, :b])

      assert focus.next_keys == [%Event.Key{code: "tab"}]

      assert focus.prev_keys == [
               %Event.Key{code: "back_tab"},
               %Event.Key{code: "tab", modifiers: ["shift"]}
             ]
    end

    test "stores overridden next/prev keys" do
      next = [%Event.Key{code: "right", modifiers: ["ctrl"]}]
      prev = [%Event.Key{code: "left", modifiers: ["ctrl"]}]
      focus = Focus.new([:a, :b], next_keys: next, prev_keys: prev)

      assert focus.next_keys == next
      assert focus.prev_keys == prev
    end

    test "raises on an empty ID list" do
      assert_raise ArgumentError, ~r/non-empty/, fn -> Focus.new([]) end
    end

    test "raises on duplicate IDs" do
      assert_raise ArgumentError, ~r/unique/, fn -> Focus.new([:a, :b, :a]) end
    end

    test "raises on non-atom IDs" do
      assert_raise ArgumentError, ~r/must be atoms/, fn -> Focus.new([:a, "b"]) end
    end

    test "raises when :initial is not in the ring" do
      assert_raise ArgumentError, ~r/not found/, fn ->
        Focus.new([:a, :b], initial: :nope)
      end
    end
  end

  describe "focused?/2" do
    test "returns true for the current ID, false otherwise" do
      focus = Focus.new([:a, :b, :c], initial: :b)
      refute Focus.focused?(focus, :a)
      assert Focus.focused?(focus, :b)
      refute Focus.focused?(focus, :c)
    end
  end

  describe "focus/2" do
    test "jumps to the given ID" do
      focus = Focus.new([:a, :b, :c]) |> Focus.focus(:c)
      assert Focus.current(focus) == :c
    end

    test "raises on an unknown ID" do
      focus = Focus.new([:a, :b, :c])

      assert_raise ArgumentError, ~r/not found/, fn ->
        Focus.focus(focus, :nope)
      end
    end
  end

  describe "next/1 and prev/1" do
    test "next advances by one" do
      focus = Focus.new([:a, :b, :c])
      assert Focus.current(Focus.next(focus)) == :b
    end

    test "next wraps from last to first" do
      focus = Focus.new([:a, :b, :c], initial: :c)
      assert Focus.current(Focus.next(focus)) == :a
    end

    test "prev retreats by one" do
      focus = Focus.new([:a, :b, :c], initial: :b)
      assert Focus.current(Focus.prev(focus)) == :a
    end

    test "prev wraps from first to last" do
      focus = Focus.new([:a, :b, :c])
      assert Focus.current(Focus.prev(focus)) == :c
    end
  end

  describe "handle_key/2" do
    setup do
      %{focus: Focus.new([:a, :b, :c])}
    end

    test "Tab advances focus and consumes the event", %{focus: focus} do
      assert {new_focus, nil} = Focus.handle_key(focus, %Event.Key{code: "tab"})
      assert Focus.current(new_focus) == :b
    end

    test "back_tab retreats focus and consumes the event", %{focus: focus} do
      assert {new_focus, nil} = Focus.handle_key(focus, %Event.Key{code: "back_tab"})
      assert Focus.current(new_focus) == :c
    end

    test "Shift+Tab retreats focus and consumes the event", %{focus: focus} do
      event = %Event.Key{code: "tab", modifiers: ["shift"]}
      assert {new_focus, nil} = Focus.handle_key(focus, event)
      assert Focus.current(new_focus) == :c
    end

    test "modifier comparison is order-independent" do
      next = [%Event.Key{code: "n", modifiers: ["ctrl", "shift"]}]
      focus = Focus.new([:a, :b], next_keys: next)

      event = %Event.Key{code: "n", modifiers: ["shift", "ctrl"]}
      assert {new_focus, nil} = Focus.handle_key(focus, event)
      assert Focus.current(new_focus) == :b
    end

    test ":kind is ignored by the matcher", %{focus: focus} do
      event = %Event.Key{code: "tab", kind: "repeat"}
      assert {new_focus, nil} = Focus.handle_key(focus, event)
      assert Focus.current(new_focus) == :b
    end

    test "non-matching keys pass through untouched", %{focus: focus} do
      event = %Event.Key{code: "a", kind: "press"}
      assert {^focus, ^event} = Focus.handle_key(focus, event)
    end

    test "custom :next_keys fully override the default" do
      focus =
        Focus.new([:a, :b],
          next_keys: [%Event.Key{code: "right", modifiers: ["ctrl"]}]
        )

      # Default Tab no longer advances.
      assert {^focus, %Event.Key{code: "tab"}} =
               Focus.handle_key(focus, %Event.Key{code: "tab"})

      # Custom key does.
      event = %Event.Key{code: "right", modifiers: ["ctrl"]}
      assert {new_focus, nil} = Focus.handle_key(focus, event)
      assert Focus.current(new_focus) == :b
    end
  end

  describe "set_region/3 and region/2" do
    test "stores a rect under the given ID" do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}
      focus = Focus.new([:a, :b]) |> Focus.set_region(:a, rect)

      assert Focus.region(focus, :a) == rect
      assert Focus.region(focus, :b) == nil
    end

    test "overwrites a previously stored rect" do
      first = %Rect{x: 0, y: 0, width: 5, height: 1}
      second = %Rect{x: 10, y: 0, width: 5, height: 1}

      focus =
        Focus.new([:a])
        |> Focus.set_region(:a, first)
        |> Focus.set_region(:a, second)

      assert Focus.region(focus, :a) == second
    end

    test "raises when the ID is not in the ring" do
      assert_raise ArgumentError, ~r/not found in focus ring/, fn ->
        Focus.set_region(Focus.new([:a]), :unknown, %Rect{x: 0, y: 0, width: 1, height: 1})
      end
    end
  end

  describe "set_regions/2" do
    test "registers every entry at once" do
      rects = %{
        a: %Rect{x: 0, y: 0, width: 5, height: 1},
        b: %Rect{x: 0, y: 1, width: 5, height: 1}
      }

      focus = Focus.new([:a, :b]) |> Focus.set_regions(rects)

      assert Focus.region(focus, :a) == rects.a
      assert Focus.region(focus, :b) == rects.b
    end

    test "raises if any ID is missing from the ring" do
      assert_raise ArgumentError, ~r/not found in focus ring/, fn ->
        Focus.set_regions(Focus.new([:a]), %{ghost: %Rect{x: 0, y: 0, width: 1, height: 1}})
      end
    end
  end

  describe "at/3" do
    test "returns the ID whose region contains the point" do
      focus =
        Focus.new([:a, :b])
        |> Focus.set_region(:a, %Rect{x: 0, y: 0, width: 10, height: 3})
        |> Focus.set_region(:b, %Rect{x: 0, y: 3, width: 10, height: 3})

      assert Focus.at(focus, 5, 1) == :a
      assert Focus.at(focus, 5, 4) == :b
    end

    test "returns nil when no region contains the point" do
      focus = Focus.new([:a]) |> Focus.set_region(:a, %Rect{x: 0, y: 0, width: 5, height: 1})

      assert Focus.at(focus, 100, 100) == nil
    end

    test "returns nil with no regions registered" do
      assert Focus.at(Focus.new([:a]), 0, 0) == nil
    end

    test "picks the smallest region when regions overlap" do
      focus =
        Focus.new([:outer, :inner])
        |> Focus.set_region(:outer, %Rect{x: 0, y: 0, width: 10, height: 10})
        |> Focus.set_region(:inner, %Rect{x: 2, y: 2, width: 2, height: 2})

      assert Focus.at(focus, 3, 3) == :inner
      assert Focus.at(focus, 8, 8) == :outer
    end

    test "treats region boundaries as half-open: top-left included, bottom-right excluded" do
      focus =
        Focus.new([:a])
        |> Focus.set_region(:a, %Rect{x: 2, y: 3, width: 4, height: 2})

      assert Focus.at(focus, 2, 3) == :a
      assert Focus.at(focus, 5, 4) == :a
      assert Focus.at(focus, 6, 4) == nil
      assert Focus.at(focus, 5, 5) == nil
      assert Focus.at(focus, 1, 3) == nil
    end
  end

  describe "handle_mouse/2" do
    setup do
      focus =
        Focus.new([:a, :b])
        |> Focus.set_region(:a, %Rect{x: 0, y: 0, width: 10, height: 3})
        |> Focus.set_region(:b, %Rect{x: 0, y: 3, width: 10, height: 3})

      %{focus: focus}
    end

    test "left-button down inside a region focuses that ID and passes the event through",
         %{focus: focus} do
      click = %Event.Mouse{kind: "down", button: "left", x: 5, y: 4}

      assert {new_focus, ^click} = Focus.handle_mouse(focus, click)
      assert Focus.current(new_focus) == :b
    end

    test "left-button down outside any region leaves focus untouched", %{focus: focus} do
      click = %Event.Mouse{kind: "down", button: "left", x: 99, y: 99}

      assert {new_focus, ^click} = Focus.handle_mouse(focus, click)
      assert Focus.current(new_focus) == Focus.current(focus)
    end

    test "right and middle clicks never move focus", %{focus: focus} do
      for button <- ["right", "middle"] do
        event = %Event.Mouse{kind: "down", button: button, x: 5, y: 4}
        assert {new_focus, ^event} = Focus.handle_mouse(focus, event)
        assert Focus.current(new_focus) == Focus.current(focus)
      end
    end

    test "non-down kinds are pass-through with focus untouched", %{focus: focus} do
      for kind <- ["up", "drag", "moved", "scroll_up", "scroll_down"] do
        event = %Event.Mouse{kind: kind, button: "left", x: 5, y: 4}
        assert {new_focus, ^event} = Focus.handle_mouse(focus, event)
        assert Focus.current(new_focus) == Focus.current(focus)
      end
    end

    test "works with no regions registered" do
      focus = Focus.new([:a, :b])
      click = %Event.Mouse{kind: "down", button: "left", x: 0, y: 0}

      assert {^focus, ^click} = Focus.handle_mouse(focus, click)
    end
  end
end
