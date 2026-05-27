defmodule ExRatatui.Widgets.BlockTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.Widgets.Block.Title

  alias ExRatatui.Bridge
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Block

  setup do
    terminal = ExRatatui.init_test_terminal(60, 15)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
  end

  describe "Block widget" do
    test "encoding a standalone block does not raise", %{terminal: terminal} do
      block = %Block{
        title: "My Block",
        borders: [:all],
        border_type: :rounded,
        style: %Style{fg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{block, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "My Block"
    end

    test "block with individual borders", %{terminal: terminal} do
      block = %Block{borders: [:top, :bottom], border_type: :plain}
      rect = %Rect{x: 0, y: 0, width: 20, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{block, rect}])
    end

    test "block with padding", %{terminal: terminal} do
      block = %Block{
        borders: [:all],
        padding: {1, 1, 1, 1}
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{block, rect}])
    end
  end

  describe "multi-title rendering" do
    test "title + right-aligned secondary title both appear on top border", %{
      terminal: terminal
    } do
      block = %Block{
        title: "src/lib.rs",
        titles: [%Block.Title{content: "[3/12]", alignment: :right}],
        borders: [:all]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{block, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "src/lib.rs"
      assert content =~ "[3/12]"
    end

    test "bottom title renders on bottom border", %{terminal: terminal} do
      block = %Block{
        title: "Top",
        titles: [%Block.Title{content: "Bottom", position: :bottom}],
        borders: [:all]
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 4}

      assert :ok = ExRatatui.draw(terminal, [{block, rect}])
      lines = ExRatatui.get_buffer_content(terminal) |> String.split("\n", trim: true)
      assert hd(lines) =~ "Top"
      assert Enum.at(lines, 3) =~ "Bottom"
    end

    test "title_position: :bottom moves the default position for unanchored titles",
         %{terminal: terminal} do
      block = %Block{
        titles: ["status"],
        title_position: :bottom,
        borders: [:all]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{block, rect}])
      lines = ExRatatui.get_buffer_content(terminal) |> String.split("\n", trim: true)
      assert Enum.at(lines, 2) =~ "status"
    end
  end

  describe "title-field validation" do
    test "title_position rejects unknown atoms" do
      block = %Block{title_position: :middle}
      rect = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert_raise ArgumentError, ~r/title_position expected :top or :bottom/, fn ->
        Bridge.encode_commands!([{block, rect}])
      end
    end

    test "title_alignment rejects unknown atoms" do
      block = %Block{title_alignment: :justified}
      rect = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert_raise ArgumentError, ~r/title_alignment expected :left, :center, or :right/, fn ->
        Bridge.encode_commands!([{block, rect}])
      end
    end

    test "Block.Title with invalid position raises" do
      block = %Block{titles: [%Block.Title{content: "x", position: :middle}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert_raise ArgumentError, ~r/expected :top or :bottom/, fn ->
        Bridge.encode_commands!([{block, rect}])
      end
    end

    test "Block.Title with invalid alignment raises" do
      block = %Block{titles: [%Block.Title{content: "x", alignment: :justify}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert_raise ArgumentError, ~r/expected :left, :center, or :right/, fn ->
        Bridge.encode_commands!([{block, rect}])
      end
    end

    test "Block.Title with nil :content raises" do
      block = %Block{titles: [%Block.Title{content: nil}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert_raise ArgumentError, ~r/has nil :content/, fn ->
        Bridge.encode_commands!([{block, rect}])
      end
    end

    test "titles list accepts a raw line-like entry without wrapping in Block.Title",
         %{terminal: terminal} do
      block = %Block{titles: ["plain"], borders: [:all]}
      rect = %Rect{x: 0, y: 0, width: 20, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{block, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "plain"
    end

    test "titles list rejects entries that are neither Block.Title nor line-like" do
      block = %Block{titles: [{:not, :a, :title}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert_raise ArgumentError, ~r/expected %Block\.Title\{\} or a line-like value/, fn ->
        Bridge.encode_commands!([{block, rect}])
      end
    end

    test "title_alignment: nil raises with the dedicated error" do
      block = %Block{title_alignment: nil}
      rect = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert_raise ArgumentError, ~r/expected :left, :center, or :right/, fn ->
        Bridge.encode_commands!([{block, rect}])
      end
    end

    test "title_position: nil raises with the dedicated error" do
      block = %Block{title_position: nil}
      rect = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert_raise ArgumentError, ~r/expected :top or :bottom/, fn ->
        Bridge.encode_commands!([{block, rect}])
      end
    end
  end
end
