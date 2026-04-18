defmodule ExRatatui.FocusTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.Focus

  alias ExRatatui.Event
  alias ExRatatui.Focus

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
end
