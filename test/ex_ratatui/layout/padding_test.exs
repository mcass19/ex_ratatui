defmodule ExRatatui.Layout.PaddingTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.Layout.Padding

  alias ExRatatui.Layout.Padding
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Block

  test "uniform/1 pads all four sides equally" do
    assert Padding.uniform(3) == {3, 3, 3, 3}
    assert Padding.uniform(0) == {0, 0, 0, 0}
  end

  test "symmetric/2 splits horizontal and vertical" do
    assert Padding.symmetric(4, 2) == {4, 4, 2, 2}
  end

  test "horizontal/1 and vertical/1 zero the other axis" do
    assert Padding.horizontal(5) == {5, 5, 0, 0}
    assert Padding.vertical(5) == {0, 0, 5, 5}
  end

  test "new/4 is the identity constructor" do
    assert Padding.new(1, 2, 3, 4) == {1, 2, 3, 4}
  end

  test "the result drops straight into a Block and renders" do
    terminal = ExRatatui.init_test_terminal(20, 6)
    on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

    block = %Block{borders: [:all], padding: Padding.uniform(1)}
    rect = %Rect{x: 0, y: 0, width: 20, height: 6}

    assert :ok = ExRatatui.draw(terminal, [{block, rect}])
  end
end
