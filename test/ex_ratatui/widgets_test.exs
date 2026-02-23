defmodule ExRatatui.WidgetsTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Native
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Gauge, List, Paragraph, Table}

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

  describe "Paragraph with block" do
    test "paragraph inside a block", %{terminal: terminal} do
      paragraph = %Paragraph{
        text: "Inside a box",
        style: %Style{fg: :cyan},
        block: %Block{
          title: "Title",
          borders: [:all],
          border_type: :rounded,
          border_style: %Style{fg: :yellow}
        }
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Inside a box"
      assert content =~ "Title"
    end
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
  end

  describe "Table widget" do
    test "simple table", %{terminal: terminal} do
      table = %Table{
        rows: [["Alice", "30"], ["Bob", "25"]],
        widths: [{:length, 15}, {:length, 10}]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Alice"
      assert content =~ "Bob"
    end

    test "table with header", %{terminal: terminal} do
      table = %Table{
        rows: [["Alice", "30"], ["Bob", "25"]],
        header: ["Name", "Age"],
        widths: [{:length, 15}, {:length, 10}]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Name"
      assert content =~ "Age"
      assert content =~ "Alice"
    end

    test "table with selection and block", %{terminal: terminal} do
      table = %Table{
        rows: [["Row 1"], ["Row 2"], ["Row 3"]],
        widths: [{:percentage, 100}],
        highlight_style: %Style{fg: :cyan},
        highlight_symbol: "> ",
        selected: 0,
        block: %Block{title: "Data", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Data"
      assert content =~ "Row 1"
    end

    test "table with percentage widths", %{terminal: terminal} do
      table = %Table{
        rows: [["A", "B", "C"]],
        widths: [{:percentage, 33}, {:percentage, 33}, {:percentage, 34}]
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "A"
      assert content =~ "B"
      assert content =~ "C"
    end
  end

  describe "Gauge widget" do
    test "basic gauge", %{terminal: terminal} do
      gauge = %Gauge{
        ratio: 0.5,
        gauge_style: %Style{fg: :green}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{gauge, rect}])
    end

    test "gauge with label and block", %{terminal: terminal} do
      gauge = %Gauge{
        ratio: 0.75,
        label: "75%",
        gauge_style: %Style{fg: :blue},
        block: %Block{title: "Progress", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{gauge, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "75%"
      assert content =~ "Progress"
    end

    test "gauge with zero ratio", %{terminal: terminal} do
      gauge = %Gauge{ratio: 0.0}
      rect = %Rect{x: 0, y: 0, width: 20, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{gauge, rect}])
    end

    test "gauge with integer ratio coerced to float", %{terminal: terminal} do
      gauge = %Gauge{ratio: 1}
      rect = %Rect{x: 0, y: 0, width: 20, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{gauge, rect}])
    end
  end

  describe "mixed widgets in one frame" do
    test "multiple widget types in a single draw call", %{terminal: terminal} do
      widgets = [
        {%Paragraph{text: "Header"}, %Rect{x: 0, y: 0, width: 40, height: 3}},
        {%List{items: ["a", "b"]}, %Rect{x: 0, y: 3, width: 40, height: 5}},
        {%Gauge{ratio: 0.5}, %Rect{x: 0, y: 8, width: 40, height: 1}}
      ]

      assert :ok = ExRatatui.draw(terminal, widgets)
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Header"
      assert content =~ "a"
      assert content =~ "b"
    end
  end

  describe "encoding validation (no terminal needed)" do
    test "block struct has correct defaults" do
      block = %Block{}
      assert block.title == nil
      assert block.borders == []
      assert block.border_type == :plain
      assert block.padding == {0, 0, 0, 0}
    end

    test "list struct has correct defaults" do
      list = %List{}
      assert list.items == []
      assert list.selected == nil
      assert list.highlight_symbol == nil
    end

    test "table struct has correct defaults" do
      table = %Table{}
      assert table.rows == []
      assert table.header == nil
      assert table.widths == []
      assert table.column_spacing == 1
    end

    test "gauge struct has correct defaults" do
      gauge = %Gauge{}
      assert gauge.ratio == 0.0
      assert gauge.label == nil
    end
  end
end
