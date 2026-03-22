defmodule ExRatatui.WidgetsTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Native
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style

  alias ExRatatui.Widgets.{
    Block,
    Clear,
    Gauge,
    LineGauge,
    List,
    Paragraph,
    Scrollbar,
    Table,
    Tabs
  }

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

  describe "Clear widget" do
    test "clears an area to spaces", %{terminal: terminal} do
      paragraph = %Paragraph{text: "Hello World!"}
      full = %Rect{x: 0, y: 0, width: 40, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, full}])
      assert ExRatatui.get_buffer_content(terminal) =~ "Hello World!"

      clear_rect = %Rect{x: 0, y: 0, width: 12, height: 1}

      assert :ok =
               ExRatatui.draw(terminal, [
                 {paragraph, full},
                 {%Clear{}, clear_rect}
               ])

      content = ExRatatui.get_buffer_content(terminal)
      refute String.starts_with?(content, "Hello")
    end

    test "clear struct has no fields" do
      assert %Clear{} == %Clear{}
      assert Map.keys(%Clear{}) == [:__struct__]
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

    test "tabs struct has correct defaults" do
      tabs = %Tabs{}
      assert tabs.titles == []
      assert tabs.selected == nil
      assert tabs.divider == nil
      assert tabs.padding == {1, 1}
    end

    test "scrollbar struct has correct defaults" do
      scrollbar = %Scrollbar{}
      assert scrollbar.orientation == :vertical_right
      assert scrollbar.content_length == 0
      assert scrollbar.position == 0
      assert scrollbar.viewport_content_length == nil
    end

    test "line_gauge struct has correct defaults" do
      lg = %LineGauge{}
      assert lg.ratio == 0.0
      assert lg.label == nil
    end
  end

  describe "Tabs widget" do
    test "basic tabs with selection", %{terminal: terminal} do
      tabs = %Tabs{
        titles: ["Home", "Settings", "About"],
        selected: 0,
        highlight_style: %Style{fg: :yellow, modifiers: [:bold]}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{tabs, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Home"
      assert content =~ "Settings"
      assert content =~ "About"
    end

    test "tabs with custom divider", %{terminal: terminal} do
      tabs = %Tabs{
        titles: ["A", "B", "C"],
        selected: 1,
        divider: " | "
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{tabs, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "|"
    end

    test "tabs with block", %{terminal: terminal} do
      tabs = %Tabs{
        titles: ["Tab 1", "Tab 2"],
        selected: 0,
        block: %Block{title: "Navigation", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{tabs, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Navigation"
      assert content =~ "Tab 1"
    end

    test "tabs with no selection", %{terminal: terminal} do
      tabs = %Tabs{titles: ["X", "Y"]}
      rect = %Rect{x: 0, y: 0, width: 20, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{tabs, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "X"
    end
  end

  describe "Scrollbar widget" do
    test "vertical scrollbar renders", %{terminal: terminal} do
      scrollbar = %Scrollbar{
        content_length: 100,
        position: 10,
        orientation: :vertical_right
      }

      rect = %Rect{x: 0, y: 0, width: 1, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{scrollbar, rect}])
    end

    test "horizontal scrollbar renders", %{terminal: terminal} do
      scrollbar = %Scrollbar{
        content_length: 200,
        position: 50,
        orientation: :horizontal_bottom
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{scrollbar, rect}])
    end

    test "scrollbar with viewport_content_length", %{terminal: terminal} do
      scrollbar = %Scrollbar{
        content_length: 100,
        position: 0,
        viewport_content_length: 10
      }

      rect = %Rect{x: 0, y: 0, width: 1, height: 15}

      assert :ok = ExRatatui.draw(terminal, [{scrollbar, rect}])
    end

    test "scrollbar with all orientations", %{terminal: terminal} do
      for orientation <- [:vertical_right, :vertical_left, :horizontal_bottom, :horizontal_top] do
        scrollbar = %Scrollbar{content_length: 50, position: 25, orientation: orientation}

        {rect, _desc} =
          case orientation do
            o when o in [:vertical_right, :vertical_left] ->
              {%Rect{x: 0, y: 0, width: 1, height: 10}, "vertical"}

            _ ->
              {%Rect{x: 0, y: 0, width: 40, height: 1}, "horizontal"}
          end

        assert :ok = ExRatatui.draw(terminal, [{scrollbar, rect}])
      end
    end
  end

  describe "LineGauge widget" do
    test "basic line gauge", %{terminal: terminal} do
      lg = %LineGauge{
        ratio: 0.5,
        filled_style: %Style{fg: :green}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{lg, rect}])
    end

    test "line gauge with label and block", %{terminal: terminal} do
      lg = %LineGauge{
        ratio: 0.75,
        label: "75%",
        filled_style: %Style{fg: :blue},
        block: %Block{title: "Download", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{lg, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "75%"
      assert content =~ "Download"
    end

    test "line gauge with zero ratio", %{terminal: terminal} do
      lg = %LineGauge{ratio: 0.0}
      rect = %Rect{x: 0, y: 0, width: 20, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{lg, rect}])
    end

    test "line gauge with integer ratio coerced to float", %{terminal: terminal} do
      lg = %LineGauge{ratio: 1}
      rect = %Rect{x: 0, y: 0, width: 20, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{lg, rect}])
    end
  end
end
