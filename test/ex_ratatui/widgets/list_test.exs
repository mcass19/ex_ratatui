defmodule ExRatatui.Widgets.ListTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, List}

  setup do
    terminal = ExRatatui.init_test_terminal(60, 15)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
  end

  describe "List widget" do
    test "simple list", %{terminal: terminal} do
      list = %List{
        items: ["Alpha", "Beta", "Gamma"],
        style: %Style{fg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{list, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Alpha"
      assert content =~ "Beta"
      assert content =~ "Gamma"
    end

    test "list with selection", %{terminal: terminal} do
      list = %List{
        items: ["One", "Two", "Three"],
        highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
        highlight_symbol: ">> ",
        selected: 1
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{list, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ ">>"
      assert content =~ "Two"
    end

    test "list with block", %{terminal: terminal} do
      list = %List{
        items: ["Item A", "Item B"],
        block: %Block{title: "My List", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{list, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "My List"
      assert content =~ "Item A"
    end

    test "bottom_to_top reverses item order on screen", %{terminal: terminal} do
      list = %List{
        items: ["first", "second", "third"],
        direction: :bottom_to_top
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{list, rect}])

      [row0, row1, row2 | _] =
        ExRatatui.get_buffer_content(terminal) |> String.split("\n")

      assert row0 =~ "third"
      assert row1 =~ "second"
      assert row2 =~ "first"
    end

    test "scroll_padding keeps the selected item rendered when it would otherwise scroll off",
         %{terminal: terminal} do
      items = for i <- 0..9, do: "item #{i}"
      list = %List{items: items, selected: 9, scroll_padding: 2}
      rect = %Rect{x: 0, y: 0, width: 12, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{list, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "item 9"
    end

    test "repeat_highlight_symbol marks every wrapped row of the selected item",
         %{terminal: terminal} do
      alias ExRatatui.Text.{Line, Span}

      multi_line = %ExRatatui.Text{
        lines: [
          %Line{spans: [%Span{content: "line one"}]},
          %Line{spans: [%Span{content: "line two"}]}
        ]
      }

      list = %List{
        items: [multi_line, "other"],
        selected: 0,
        highlight_symbol: ">> ",
        repeat_highlight_symbol: true
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{list, rect}])
      [row0, row1 | _] = ExRatatui.get_buffer_content(terminal) |> String.split("\n")
      assert row0 =~ ">> "
      assert row1 =~ ">> "
    end
  end
end
