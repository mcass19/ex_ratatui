defmodule ExRatatui.WidgetsTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style

  alias ExRatatui.Widgets.{
    Bar,
    BarChart,
    Block,
    Calendar,
    Canvas,
    Checkbox,
    Clear,
    Gauge,
    LineGauge,
    List,
    Markdown,
    Paragraph,
    Popup,
    Scrollbar,
    Sparkline,
    Table,
    Tabs,
    Textarea,
    TextInput,
    Throbber,
    WidgetList
  }

  alias ExRatatui.Widgets.Canvas.{Circle, Line, Points, Rectangle}

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

  describe "Paragraph widget" do
    test "left alignment (default)", %{terminal: terminal} do
      paragraph = %Paragraph{text: "aligned left", style: %Style{fg: :white}}
      rect = %Rect{x: 0, y: 0, width: 40, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "aligned left"
    end

    test "right alignment", %{terminal: terminal} do
      paragraph = %Paragraph{text: "right", alignment: :right}
      rect = %Rect{x: 0, y: 0, width: 40, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "right"
    end

    test "word wrap renders long text across multiple rows", %{terminal: terminal} do
      paragraph = %Paragraph{
        text: "one two three four five six seven eight nine ten",
        wrap: true
      }

      rect = %Rect{x: 0, y: 0, width: 10, height: 6}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "one"
      assert content =~ "ten"
    end

    test "vertical scroll offset skips rows", %{terminal: terminal} do
      paragraph = %Paragraph{
        text: "row1\nrow2\nrow3\nrow4",
        scroll: {2, 0}
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 2}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "row1"
      assert content =~ "row3"
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

  describe "Checkbox widget" do
    test "checked checkbox renders symbol and label", %{terminal: terminal} do
      checkbox = %Checkbox{
        label: "Accept terms",
        checked: true,
        checked_style: %Style{fg: :green}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{checkbox, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "[x]"
      assert content =~ "Accept terms"
    end

    test "unchecked checkbox renders symbol and label", %{terminal: terminal} do
      checkbox = %Checkbox{
        label: "Subscribe",
        checked: false
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{checkbox, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "[ ]"
      assert content =~ "Subscribe"
    end

    test "checkbox with custom symbols", %{terminal: terminal} do
      checkbox = %Checkbox{
        label: "Custom",
        checked: true,
        checked_symbol: "✓",
        unchecked_symbol: "✗"
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{checkbox, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "✓"
    end

    test "checkbox with block", %{terminal: terminal} do
      checkbox = %Checkbox{
        label: "Wrapped",
        checked: true,
        block: %Block{title: "Options", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{checkbox, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Options"
      assert content =~ "[x]"
    end
  end

  describe "TextInput widget" do
    test "renders text input with value", %{terminal: terminal} do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "h")
      ExRatatui.text_input_handle_key(state, "e")
      ExRatatui.text_input_handle_key(state, "l")
      ExRatatui.text_input_handle_key(state, "l")
      ExRatatui.text_input_handle_key(state, "o")

      input = %TextInput{
        state: state,
        style: %Style{fg: :white},
        cursor_style: %Style{fg: :black, bg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "hello"
    end

    test "renders placeholder when empty", %{terminal: terminal} do
      state = ExRatatui.text_input_new()

      input = %TextInput{
        state: state,
        placeholder: "Type here...",
        placeholder_style: %Style{fg: :dark_gray},
        cursor_style: %Style{fg: :black, bg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Type here..."
    end

    test "renders with block", %{terminal: terminal} do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "test value")

      input = %TextInput{
        state: state,
        style: %Style{fg: :white},
        cursor_style: %Style{fg: :black, bg: :white},
        block: %Block{title: "Search", borders: [:all], border_type: :rounded}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Search"
      assert content =~ "test value"
    end

    test "text_input struct has correct defaults" do
      input = %TextInput{}
      assert input.state == nil
      assert input.placeholder == nil
      assert input.block == nil
      assert input.style == %Style{}
      assert input.cursor_style == %Style{}
      assert input.placeholder_style == %Style{}
    end
  end

  describe "TextInput state management" do
    test "new text input has empty value" do
      state = ExRatatui.text_input_new()
      assert ExRatatui.text_input_get_value(state) == ""
    end

    test "typing characters builds up value" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "a")
      ExRatatui.text_input_handle_key(state, "b")
      ExRatatui.text_input_handle_key(state, "c")
      assert ExRatatui.text_input_get_value(state) == "abc"
    end

    test "set_value replaces content" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "x")
      ExRatatui.text_input_set_value(state, "hello world")
      assert ExRatatui.text_input_get_value(state) == "hello world"
    end

    test "set_value to empty string clears input" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "something")
      ExRatatui.text_input_set_value(state, "")
      assert ExRatatui.text_input_get_value(state) == ""
    end

    test "cursor starts at 0" do
      state = ExRatatui.text_input_new()
      assert ExRatatui.text_input_cursor(state) == 0
    end

    test "cursor advances with each character typed" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "a")
      ExRatatui.text_input_handle_key(state, "b")
      assert ExRatatui.text_input_cursor(state) == 2
    end

    test "backspace deletes character before cursor" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      ExRatatui.text_input_handle_key(state, "backspace")
      assert ExRatatui.text_input_get_value(state) == "ab"
    end

    test "backspace on empty input is a no-op" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_handle_key(state, "backspace")
      assert ExRatatui.text_input_get_value(state) == ""
      assert ExRatatui.text_input_cursor(state) == 0
    end

    test "delete removes character at cursor" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      # Move cursor to beginning
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "delete")
      assert ExRatatui.text_input_get_value(state) == "bc"
    end

    test "left arrow moves cursor back" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      # Cursor is at end (3)
      ExRatatui.text_input_handle_key(state, "left")
      assert ExRatatui.text_input_cursor(state) == 2
    end

    test "right arrow moves cursor forward" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "right")
      assert ExRatatui.text_input_cursor(state) == 1
    end

    test "home moves cursor to beginning" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "hello")
      ExRatatui.text_input_handle_key(state, "home")
      assert ExRatatui.text_input_cursor(state) == 0
    end

    test "end moves cursor to end" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "hello")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "end")
      assert ExRatatui.text_input_cursor(state) == 5
    end

    test "inserting in the middle of text" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "ac")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "right")
      ExRatatui.text_input_handle_key(state, "b")
      assert ExRatatui.text_input_get_value(state) == "abc"
      assert ExRatatui.text_input_cursor(state) == 2
    end

    test "left at beginning is a no-op" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      ExRatatui.text_input_handle_key(state, "home")
      ExRatatui.text_input_handle_key(state, "left")
      assert ExRatatui.text_input_cursor(state) == 0
    end

    test "right at end is a no-op" do
      state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(state, "abc")
      ExRatatui.text_input_handle_key(state, "right")
      assert ExRatatui.text_input_cursor(state) == 3
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

    test "checkbox struct has correct defaults" do
      cb = %Checkbox{}
      assert cb.label == ""
      assert cb.checked == false
      assert cb.checked_symbol == nil
      assert cb.unchecked_symbol == nil
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

    test "bar struct has correct defaults" do
      bar = %Bar{}
      assert bar.label == ""
      assert bar.value == 0
      assert bar.style == nil
      assert bar.text_value == nil
    end

    test "bar_chart struct has correct defaults" do
      chart = %BarChart{}
      assert chart.data == []
      assert chart.bar_width == 1
      assert chart.bar_gap == 1
      assert chart.max == nil
      assert chart.direction == :vertical
      assert chart.block == nil
    end

    test "bar_chart rejects negative bar value" do
      chart = %BarChart{data: [%Bar{label: "x", value: -1}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/non-negative integer/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
    end

    test "bar_chart rejects float bar value" do
      chart = %BarChart{data: [%Bar{label: "x", value: 3.5}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/non-negative integer/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
    end

    test "bar_chart rejects non-Bar entry in data" do
      chart = %BarChart{data: [{"Elixir", 80}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/list of %Bar\{\}/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
    end

    test "bar_chart rejects non-list data" do
      chart = %BarChart{data: "not a list"}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/list of %Bar\{\}/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
    end

    test "bar_chart rejects unknown direction" do
      chart = %BarChart{data: [], direction: :diagonal}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/:vertical or :horizontal/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
    end

    test "sparkline struct has correct defaults" do
      sparkline = %Sparkline{}
      assert sparkline.data == []
      assert sparkline.style == nil
      assert sparkline.max == nil
      assert sparkline.direction == :left_to_right
      assert sparkline.bar_set == :nine_levels
      assert sparkline.absent_value_style == nil
      assert sparkline.absent_value_symbol == nil
      assert sparkline.block == nil
    end

    test "sparkline rejects non-list data" do
      sparkline = %Sparkline{data: "nope"}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/list of non-negative integers/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "sparkline rejects negative data entry" do
      sparkline = %Sparkline{data: [1, -2, 3]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/non-negative integer/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "sparkline rejects float data entry" do
      sparkline = %Sparkline{data: [1, 2.5, 3]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/non-negative integer/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "sparkline rejects unknown direction" do
      sparkline = %Sparkline{data: [1, 2], direction: :diagonal}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/:left_to_right or :right_to_left/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "sparkline rejects unknown bar_set atom" do
      sparkline = %Sparkline{data: [1, 2], bar_set: :fancy}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/bar_set/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "sparkline rejects empty custom bar_set list" do
      sparkline = %Sparkline{data: [1, 2], bar_set: []}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/bar_set/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "sparkline rejects non-string custom bar_set entry" do
      sparkline = %Sparkline{data: [1, 2], bar_set: [" ", :oops]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/bar_set/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "sparkline rejects non-integer max" do
      sparkline = %Sparkline{data: [1, 2], max: 3.5}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/max/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "sparkline rejects negative max" do
      sparkline = %Sparkline{data: [1, 2], max: -1}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/max/, fn ->
        ExRatatui.Bridge.encode_commands!([{sparkline, rect}])
      end
    end

    test "calendar rejects non-Date display_date" do
      calendar = %Calendar{display_date: {2026, 3, 15}}
      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert_raise ArgumentError, ~r/display_date/, fn ->
        ExRatatui.Bridge.encode_commands!([{calendar, rect}])
      end
    end

    test "calendar rejects non-boolean show_month_header" do
      calendar = %Calendar{display_date: ~D[2026-03-15], show_month_header: "yes"}
      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert_raise ArgumentError, ~r/show_month_header/, fn ->
        ExRatatui.Bridge.encode_commands!([{calendar, rect}])
      end
    end

    test "calendar rejects non-boolean show_weekdays_header" do
      calendar = %Calendar{display_date: ~D[2026-03-15], show_weekdays_header: 1}
      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert_raise ArgumentError, ~r/show_weekdays_header/, fn ->
        ExRatatui.Bridge.encode_commands!([{calendar, rect}])
      end
    end

    test "calendar rejects non-list/non-map events" do
      calendar = %Calendar{display_date: ~D[2026-03-15], events: "nope"}
      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert_raise ArgumentError, ~r/events/, fn ->
        ExRatatui.Bridge.encode_commands!([{calendar, rect}])
      end
    end

    test "calendar rejects event entries that are not {Date, Style}" do
      calendar = %Calendar{
        display_date: ~D[2026-03-15],
        events: [{~D[2026-03-01], "bad"}]
      }

      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert_raise ArgumentError, ~r/events/, fn ->
        ExRatatui.Bridge.encode_commands!([{calendar, rect}])
      end
    end

    test "canvas rejects non-tuple x_bounds" do
      canvas = %Canvas{x_bounds: [0.0, 10.0], y_bounds: {0.0, 10.0}, shapes: []}
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/x_bounds/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects inverted bounds" do
      canvas = %Canvas{x_bounds: {10.0, 0.0}, y_bounds: {0.0, 10.0}, shapes: []}
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/x_bounds/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects unknown marker" do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        marker: :quadrant,
        shapes: []
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/marker/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects non-list shapes" do
      canvas = %Canvas{x_bounds: {0.0, 10.0}, y_bounds: {0.0, 10.0}, shapes: "nope"}
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/shapes/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects shape with missing color" do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Line{x1: 0.0, y1: 0.0, x2: 1.0, y2: 1.0}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/color/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects rectangle with negative width" do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Rectangle{x: 0.0, y: 0.0, width: -1.0, height: 2.0, color: :red}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/width/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects circle with negative radius" do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Circle{x: 5.0, y: 5.0, radius: -1.0, color: :blue}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/radius/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects points coord that is not a tuple" do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Points{coords: [[1.0, 2.0]], color: :green}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/coords/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects unknown shape struct" do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%{foo: :bar}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert_raise ArgumentError, ~r/shape/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Line with missing required fields" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}
      base = %Canvas{x_bounds: {0.0, 10.0}, y_bounds: {0.0, 10.0}, shapes: []}

      for {attrs, field} <- [
            {[y1: 0, x2: 0, y2: 0, color: :red], "x1"},
            {[x1: 0, x2: 0, y2: 0, color: :red], "y1"},
            {[x1: 0, y1: 0, y2: 0, color: :red], "x2"},
            {[x1: 0, y1: 0, x2: 0, color: :red], "y2"}
          ] do
        canvas = %{base | shapes: [struct(Line, attrs)]}

        assert_raise ArgumentError, ~r/Line\.#{field} is required/, fn ->
          ExRatatui.Bridge.encode_commands!([{canvas, rect}])
        end
      end
    end

    test "canvas rejects Rectangle with missing required fields" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}
      base = %Canvas{x_bounds: {0.0, 10.0}, y_bounds: {0.0, 10.0}, shapes: []}

      for {attrs, field} <- [
            {[y: 0, width: 1, height: 1, color: :red], "x"},
            {[x: 0, width: 1, height: 1, color: :red], "y"},
            {[x: 0, y: 0, height: 1, color: :red], "width"},
            {[x: 0, y: 0, width: 1, color: :red], "height"},
            {[x: 0, y: 0, width: 1, height: 1], "color"}
          ] do
        canvas = %{base | shapes: [struct(Rectangle, attrs)]}

        assert_raise ArgumentError, ~r/Rectangle\.#{field} is required/, fn ->
          ExRatatui.Bridge.encode_commands!([{canvas, rect}])
        end
      end
    end

    test "canvas rejects Circle with missing required fields" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}
      base = %Canvas{x_bounds: {0.0, 10.0}, y_bounds: {0.0, 10.0}, shapes: []}

      for {attrs, field} <- [
            {[y: 0, radius: 1, color: :red], "x"},
            {[x: 0, radius: 1, color: :red], "y"},
            {[x: 0, y: 0, color: :red], "radius"},
            {[x: 0, y: 0, radius: 1], "color"}
          ] do
        canvas = %{base | shapes: [struct(Circle, attrs)]}

        assert_raise ArgumentError, ~r/Circle\.#{field} is required/, fn ->
          ExRatatui.Bridge.encode_commands!([{canvas, rect}])
        end
      end
    end

    test "canvas rejects Points with missing color" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Points{coords: [{1.0, 1.0}]}]
      }

      assert_raise ArgumentError, ~r/Points\.color is required/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Points with non-list coords" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Points{coords: "bogus", color: :red}]
      }

      assert_raise ArgumentError, ~r/expected a list of \{x, y\} tuples/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Line with non-number coordinate" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Line{x1: "bad", y1: 0, x2: 5, y2: 5, color: :red}]
      }

      assert_raise ArgumentError, ~r/Line\.x1 expected a number/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Rectangle with non-number width" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Rectangle{x: 0, y: 0, width: "bad", height: 1, color: :red}]
      }

      assert_raise ArgumentError, ~r/Rectangle\.width expected a non-negative number/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects atom bounds field" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{x_bounds: :nope, y_bounds: {0.0, 10.0}, shapes: []}

      assert_raise ArgumentError, ~r/x_bounds expected \{min, max\} tuple of numbers/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
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

  describe "BarChart widget" do
    test "basic vertical chart with labels", %{terminal: terminal} do
      chart = %BarChart{
        data: [
          %Bar{label: "Elixir", value: 80},
          %Bar{label: "Rust", value: 95}
        ],
        bar_width: 6,
        bar_gap: 2,
        bar_style: %Style{fg: :cyan}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Elixir"
      assert content =~ "Rust"
    end

    test "horizontal direction", %{terminal: terminal} do
      chart = %BarChart{
        data: [%Bar{label: "Go", value: 60}],
        direction: :horizontal,
        max: 100
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 4}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Go"
    end

    test "per-bar style override and text_value", %{terminal: terminal} do
      chart = %BarChart{
        data: [
          %Bar{label: "Default", value: 10},
          %Bar{label: "Red", value: 20, style: %Style{fg: :red}, text_value: "20!"}
        ],
        bar_width: 4,
        bar_style: %Style{fg: :blue},
        max: 30
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "20!"
    end

    test "with block title", %{terminal: terminal} do
      chart = %BarChart{
        data: [%Bar{label: "A", value: 1}],
        block: %Block{title: " Traffic ", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Traffic"
    end

    test "auto-scales when max is nil", %{terminal: terminal} do
      chart = %BarChart{
        data: [
          %Bar{label: "A", value: 1},
          %Bar{label: "B", value: 100}
        ]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
    end

    test "empty data list renders", %{terminal: terminal} do
      chart = %BarChart{data: []}
      rect = %Rect{x: 0, y: 0, width: 20, height: 4}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
    end
  end

  describe "Sparkline widget" do
    test "basic left-to-right data renders", %{terminal: terminal} do
      sparkline = %Sparkline{
        data: [0, 1, 3, 5, 8, 3, 1],
        style: %Style{fg: :cyan}
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{sparkline, rect}])
    end

    test "right-to-left direction renders", %{terminal: terminal} do
      sparkline = %Sparkline{
        data: [1, 2, 8],
        direction: :right_to_left,
        max: 8
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{sparkline, rect}])
    end

    test "auto-scales when max is nil", %{terminal: terminal} do
      sparkline = %Sparkline{data: [5, 10, 15]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{sparkline, rect}])
    end

    test "absent value renders with custom symbol", %{terminal: terminal} do
      sparkline = %Sparkline{
        data: [1, nil, 5],
        max: 5,
        absent_value_symbol: "?",
        absent_value_style: %Style{fg: :red}
      }

      rect = %Rect{x: 0, y: 0, width: 6, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{sparkline, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "?"
    end

    test "three_levels bar_set preset renders", %{terminal: terminal} do
      sparkline = %Sparkline{
        data: [0, 4, 8],
        max: 8,
        bar_set: :three_levels
      }

      rect = %Rect{x: 0, y: 0, width: 6, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{sparkline, rect}])
    end

    test "custom bar_set list renders", %{terminal: terminal} do
      sparkline = %Sparkline{
        data: [0, 2, 5, 8],
        max: 8,
        bar_set: [".", "o", "O"]
      }

      rect = %Rect{x: 0, y: 0, width: 8, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{sparkline, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "O"
    end

    test "with block title renders", %{terminal: terminal} do
      sparkline = %Sparkline{
        data: [1, 2, 3, 4],
        block: %Block{title: " CPU ", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{sparkline, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "CPU"
    end

    test "empty data list renders", %{terminal: terminal} do
      sparkline = %Sparkline{data: []}
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{sparkline, rect}])
    end
  end

  describe "Calendar widget" do
    test "basic month renders", %{terminal: terminal} do
      calendar = %Calendar{display_date: ~D[2026-03-15]}
      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{calendar, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "15"
    end

    test "month and weekdays headers render", %{terminal: terminal} do
      calendar = %Calendar{
        display_date: ~D[2026-03-15],
        header_style: %Style{fg: :yellow, modifiers: [:bold]},
        weekday_style: %Style{fg: :cyan}
      }

      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{calendar, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "March"
      assert content =~ "2026"
      assert content =~ "Su"
    end

    test "events list highlights dates", %{terminal: terminal} do
      calendar = %Calendar{
        display_date: ~D[2026-03-15],
        events: [
          {~D[2026-03-10], %Style{fg: :red, modifiers: [:bold]}},
          {~D[2026-03-20], %Style{fg: :green}}
        ]
      }

      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{calendar, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "10"
      assert content =~ "20"
    end

    test "events map highlights dates", %{terminal: terminal} do
      calendar = %Calendar{
        display_date: ~D[2026-03-15],
        events: %{
          ~D[2026-03-05] => %Style{fg: :magenta},
          ~D[2026-03-25] => nil
        }
      }

      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{calendar, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "5"
    end

    test "show_surrounding fills first/last row", %{terminal: terminal} do
      calendar = %Calendar{
        display_date: ~D[2026-03-15],
        show_surrounding: %Style{fg: :dark_gray}
      }

      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{calendar, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      # February 2026 ends on the 28th; it should leak into the first row.
      assert content =~ "28"
    end

    test "calendar with block renders", %{terminal: terminal} do
      calendar = %Calendar{
        display_date: ~D[2026-03-15],
        block: %Block{title: " Calendar ", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 24, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{calendar, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Calendar"
    end

    test "leap February renders 29", %{terminal: terminal} do
      calendar = %Calendar{display_date: ~D[2024-02-15]}
      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{calendar, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "29"
    end

    test "headers can be disabled", %{terminal: terminal} do
      calendar = %Calendar{
        display_date: ~D[2026-03-15],
        show_month_header: false,
        show_weekdays_header: false
      }

      rect = %Rect{x: 0, y: 0, width: 22, height: 8}

      assert :ok = ExRatatui.draw(terminal, [{calendar, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "March"
      refute content =~ "Su"
    end
  end

  describe "Canvas widget" do
    test "renders a line", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Line{x1: 0.0, y1: 0.0, x2: 10.0, y2: 10.0, color: :red}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "renders a rectangle", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Rectangle{x: 1.0, y: 1.0, width: 5.0, height: 3.0, color: :green}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "renders a circle", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Circle{x: 5.0, y: 5.0, radius: 3.0, color: :yellow}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "renders points", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Points{coords: [{1.0, 1.0}, {2.0, 3.0}], color: :magenta}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "renders with dot marker", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        marker: :dot,
        shapes: [%Points{coords: [{5.0, 5.0}], color: :white}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "renders with background color", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        background_color: :blue,
        shapes: []
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "renders multiple shapes stacked", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [
          %Line{x1: 0.0, y1: 0.0, x2: 10.0, y2: 0.0, color: :red},
          %Circle{x: 5.0, y: 5.0, radius: 2.0, color: :blue}
        ]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "empty shapes list renders", %{terminal: terminal} do
      canvas = %Canvas{x_bounds: {0.0, 10.0}, y_bounds: {0.0, 10.0}, shapes: []}
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "canvas with block title renders", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Points{coords: [{5.0, 5.0}], color: :white}],
        block: %Block{title: " Plot ", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "Plot"
    end

    test "integer coordinates are coerced to floats", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0, 10},
        y_bounds: {0, 10},
        shapes: [%Line{x1: 0, y1: 0, x2: 10, y2: 10, color: :cyan}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end
  end

  describe "Markdown widget" do
    test "renders plain text", %{terminal: terminal} do
      md = %Markdown{content: "Hello world"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{md, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Hello world"
    end

    test "renders heading", %{terminal: terminal} do
      md = %Markdown{content: "# Title"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{md, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Title"
    end

    test "renders bold text", %{terminal: terminal} do
      md = %Markdown{content: "**bold**"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{md, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "bold"
    end

    test "renders inline code", %{terminal: terminal} do
      md = %Markdown{content: "use `code` here"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{md, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "code"
    end

    test "renders code block", %{terminal: terminal} do
      md = %Markdown{content: "```\nfn main() {}\n```"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{md, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "fn main"
    end

    test "renders bullet list", %{terminal: terminal} do
      md = %Markdown{content: "- item1\n- item2"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{md, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "item1"
      assert content =~ "item2"
    end

    test "renders with block", %{terminal: terminal} do
      md = %Markdown{
        content: "Some text",
        block: %Block{title: "Response", borders: [:all], border_type: :rounded}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{md, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Response"
    end

    test "renders empty content", %{terminal: terminal} do
      md = %Markdown{content: ""}
      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{md, rect}])
    end

    test "markdown struct has correct defaults" do
      md = %Markdown{}
      assert md.content == ""
      assert md.wrap == true
      assert md.scroll == {0, 0}
      assert md.block == nil
      assert md.style == %Style{}
    end
  end

  describe "Textarea widget" do
    test "renders textarea with value", %{terminal: terminal} do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "h", [])
      ExRatatui.textarea_handle_key(state, "e", [])
      ExRatatui.textarea_handle_key(state, "l", [])
      ExRatatui.textarea_handle_key(state, "l", [])
      ExRatatui.textarea_handle_key(state, "o", [])

      input = %Textarea{
        state: state,
        style: %Style{fg: :white},
        cursor_style: %Style{fg: :black, bg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "hello"
    end

    test "renders placeholder when empty", %{terminal: terminal} do
      state = ExRatatui.textarea_new()

      input = %Textarea{
        state: state,
        placeholder: "Type a message...",
        placeholder_style: %Style{fg: :dark_gray},
        cursor_style: %Style{fg: :black, bg: :white}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Type a message..."
    end

    test "renders with block", %{terminal: terminal} do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "test value")

      input = %Textarea{
        state: state,
        style: %Style{fg: :white},
        cursor_style: %Style{fg: :black, bg: :white},
        block: %Block{title: "Message", borders: [:all], border_type: :rounded}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{input, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Message"
      assert content =~ "test value"
    end

    test "textarea struct has correct defaults" do
      input = %Textarea{}
      assert input.state == nil
      assert input.placeholder == nil
      assert input.block == nil
      assert input.line_number_style == nil
      assert input.style == %Style{}
      assert input.cursor_style == %Style{}
    end
  end

  describe "Textarea state management" do
    test "new textarea has empty value" do
      state = ExRatatui.textarea_new()
      assert ExRatatui.textarea_get_value(state) == ""
    end

    test "handle_key with default modifiers (2-arity)" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "a")
      ExRatatui.textarea_handle_key(state, "b")
      assert ExRatatui.textarea_get_value(state) == "ab"
    end

    test "typing characters builds up value" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "a", [])
      ExRatatui.textarea_handle_key(state, "b", [])
      ExRatatui.textarea_handle_key(state, "c", [])
      assert ExRatatui.textarea_get_value(state) == "abc"
    end

    test "enter creates new line" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "h", [])
      ExRatatui.textarea_handle_key(state, "i", [])
      ExRatatui.textarea_handle_key(state, "enter", [])
      ExRatatui.textarea_handle_key(state, "x", [])
      assert ExRatatui.textarea_get_value(state) == "hi\nx"
    end

    test "set_value replaces content" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "x", [])
      ExRatatui.textarea_set_value(state, "line1\nline2")
      assert ExRatatui.textarea_get_value(state) == "line1\nline2"
    end

    test "set_value to empty clears textarea" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "something")
      ExRatatui.textarea_set_value(state, "")
      assert ExRatatui.textarea_get_value(state) == ""
    end

    test "cursor returns row and col" do
      state = ExRatatui.textarea_new()
      assert ExRatatui.textarea_cursor(state) == {0, 0}

      ExRatatui.textarea_handle_key(state, "a", [])
      ExRatatui.textarea_handle_key(state, "b", [])
      assert ExRatatui.textarea_cursor(state) == {0, 2}

      ExRatatui.textarea_handle_key(state, "enter", [])
      assert {1, 0} = ExRatatui.textarea_cursor(state)
    end

    test "line_count returns number of lines" do
      state = ExRatatui.textarea_new()
      assert ExRatatui.textarea_line_count(state) == 1

      ExRatatui.textarea_set_value(state, "a\nb\nc")
      assert ExRatatui.textarea_line_count(state) == 3
    end

    test "backspace at start of line merges with previous" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello\nworld")
      # Move to start of line 2 and backspace
      ExRatatui.textarea_handle_key(state, "down", [])
      ExRatatui.textarea_handle_key(state, "home", [])
      ExRatatui.textarea_handle_key(state, "backspace", [])
      assert ExRatatui.textarea_get_value(state) == "helloworld"
    end

    test "cursor up/down navigation" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "abc\ndef")
      # Cursor starts at (0, 0) after set_value
      ExRatatui.textarea_handle_key(state, "down", [])
      {row, _col} = ExRatatui.textarea_cursor(state)
      assert row == 1
      ExRatatui.textarea_handle_key(state, "up", [])
      {row, _col} = ExRatatui.textarea_cursor(state)
      assert row == 0
    end

    test "handle_key with modifiers" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "a", [])
      ExRatatui.textarea_handle_key(state, "b", [])
      # Ctrl+A (Emacs: beginning of line)
      ExRatatui.textarea_handle_key(state, "a", ["ctrl"])
      {_row, col} = ExRatatui.textarea_cursor(state)
      assert col == 0
    end

    test "delete key removes character at cursor" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "abcd")
      # Move to beginning
      ExRatatui.textarea_handle_key(state, "home", [])
      # Delete char at cursor (removes 'a')
      ExRatatui.textarea_handle_key(state, "delete", [])
      assert ExRatatui.textarea_get_value(state) == "bcd"
    end

    test "Ctrl+K deletes to end of line" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello world")
      # Move to beginning, then right 5 times to position after "hello"
      ExRatatui.textarea_handle_key(state, "home", [])

      for _ <- 1..5 do
        ExRatatui.textarea_handle_key(state, "right", [])
      end

      # Ctrl+K should delete from cursor to end of line
      ExRatatui.textarea_handle_key(state, "k", ["ctrl"])
      assert ExRatatui.textarea_get_value(state) == "hello"
    end

    test "Ctrl+W deletes word backward" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello world")
      # Move to end
      ExRatatui.textarea_handle_key(state, "end", [])
      # Ctrl+W should delete "world"
      ExRatatui.textarea_handle_key(state, "w", ["ctrl"])
      value = ExRatatui.textarea_get_value(state)
      assert value == "hello "
    end

    test "Ctrl+E moves cursor to end of line" do
      state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(state, "hello")
      # Move to beginning first
      ExRatatui.textarea_handle_key(state, "home", [])
      assert {0, 0} = ExRatatui.textarea_cursor(state)

      # Ctrl+E (Emacs: end of line)
      ExRatatui.textarea_handle_key(state, "e", ["ctrl"])
      {_row, col} = ExRatatui.textarea_cursor(state)
      assert col == 5
    end
  end

  describe "Popup widget" do
    test "renders popup with paragraph content", %{terminal: terminal} do
      popup = %Popup{
        content: %Paragraph{text: "Hello from popup"},
        percent_width: 80,
        percent_height: 80
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 15}

      assert :ok = ExRatatui.draw(terminal, [{popup, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Hello from popup"
    end

    test "popup clears background area", %{terminal: terminal} do
      rect = %Rect{x: 0, y: 0, width: 60, height: 15}

      # Fill every cell with X (wrap: true to fill all rows)
      bg = %Paragraph{text: String.duplicate("X", 60 * 15), wrap: true}
      assert :ok = ExRatatui.draw(terminal, [{bg, rect}])
      content_before = ExRatatui.get_buffer_content(terminal)
      x_count_before = content_before |> String.graphemes() |> Enum.count(&(&1 == "X"))
      assert x_count_before > 0

      # Now draw popup on top — it should clear its region
      popup = %Popup{
        content: %Paragraph{text: "Popup"},
        percent_width: 80,
        percent_height: 80
      }

      assert :ok = ExRatatui.draw(terminal, [{bg, rect}, {popup, rect}])
      content_after = ExRatatui.get_buffer_content(terminal)
      assert content_after =~ "Popup"

      x_count_after = content_after |> String.graphemes() |> Enum.count(&(&1 == "X"))

      assert x_count_after < x_count_before,
             "Popup should clear background Xs. Before: #{x_count_before}, After: #{x_count_after}"
    end

    test "popup with block border", %{terminal: terminal} do
      popup = %Popup{
        content: %Paragraph{text: "Content"},
        block: %Block{title: "Dialog", borders: [:all], border_type: :rounded},
        percent_width: 70,
        percent_height: 70
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 15}

      assert :ok = ExRatatui.draw(terminal, [{popup, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Dialog"
    end

    test "popup with list content", %{terminal: terminal} do
      popup = %Popup{
        content: %List{items: ["Option A", "Option B", "Option C"]},
        percent_width: 60,
        percent_height: 60
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 15}

      assert :ok = ExRatatui.draw(terminal, [{popup, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Option A"
      assert content =~ "Option B"
    end

    test "popup with fixed dimensions", %{terminal: terminal} do
      popup = %Popup{
        content: %Paragraph{text: "Fixed"},
        fixed_width: 20,
        fixed_height: 5
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 15}

      assert :ok = ExRatatui.draw(terminal, [{popup, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Fixed"
    end

    test "popup with markdown content", %{terminal: terminal} do
      popup = %Popup{
        content: %Markdown{content: "# Hello\n\nSome **bold** text."},
        percent_width: 80,
        percent_height: 80
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 15}

      assert :ok = ExRatatui.draw(terminal, [{popup, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Hello"
    end

    test "popup with nil content raises ArgumentError", %{terminal: terminal} do
      popup = %Popup{}
      rect = %Rect{x: 0, y: 0, width: 60, height: 15}

      assert_raise ArgumentError, ~r/Popup :content is required/, fn ->
        ExRatatui.draw(terminal, [{popup, rect}])
      end
    end

    test "popup struct has correct defaults" do
      popup = %Popup{}
      assert popup.content == nil
      assert popup.block == nil
      assert popup.percent_width == 60
      assert popup.percent_height == 60
      assert popup.fixed_width == nil
      assert popup.fixed_height == nil
    end
  end

  describe "Throbber widget" do
    test "renders throbber with label", %{terminal: terminal} do
      throbber = %Throbber{
        label: "Loading...",
        step: 0,
        throbber_style: %Style{fg: :cyan}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{throbber, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Loading..."
    end

    test "different steps produce different output", %{terminal: terminal} do
      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      # Use non-zero steps to avoid calc_step(0) which picks a random index
      throbber1 = %Throbber{step: 1}
      assert :ok = ExRatatui.draw(terminal, [{throbber1, rect}])
      content1 = ExRatatui.get_buffer_content(terminal)

      throbber3 = %Throbber{step: 3}
      assert :ok = ExRatatui.draw(terminal, [{throbber3, rect}])
      content3 = ExRatatui.get_buffer_content(terminal)

      assert content1 != content3, "Step 1 and step 3 should render different symbols"
    end

    test "throbber with block", %{terminal: terminal} do
      throbber = %Throbber{
        label: "Processing...",
        step: 1,
        block: %Block{title: "Status", borders: [:all], border_type: :rounded}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{throbber, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Status"
    end

    test "throbber with different animation sets", %{terminal: terminal} do
      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      for set <- [
            :braille,
            :dots,
            :ascii,
            :vertical_block,
            :horizontal_block,
            :arrow,
            :clock,
            :box_drawing,
            :quadrant_block,
            :white_square,
            :white_circle,
            :black_circle
          ] do
        throbber = %Throbber{label: "Test", step: 0, throbber_set: set}
        assert :ok = ExRatatui.draw(terminal, [{throbber, rect}])
      end
    end

    test "throbber struct has correct defaults" do
      throbber = %Throbber{}
      assert throbber.label == ""
      assert throbber.step == 0
      assert throbber.throbber_set == :braille
      assert throbber.style == %Style{}
      assert throbber.throbber_style == %Style{}
      assert throbber.block == nil
    end
  end

  describe "WidgetList widget" do
    test "renders list of paragraphs", %{terminal: terminal} do
      wl = %WidgetList{
        items: [
          {%Paragraph{text: "Message 1"}, 1},
          {%Paragraph{text: "Message 2"}, 1},
          {%Paragraph{text: "Message 3"}, 1}
        ]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Message 1"
      assert content =~ "Message 2"
      assert content =~ "Message 3"
    end

    test "renders mixed widget types", %{terminal: terminal} do
      wl = %WidgetList{
        items: [
          {%Paragraph{text: "A paragraph"}, 1},
          {%Checkbox{label: "Check me", checked: true}, 1}
        ]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "A paragraph"
      assert content =~ "Check me"
    end

    test "renders with selection", %{terminal: terminal} do
      wl = %WidgetList{
        items: [
          {%Paragraph{text: "Item A"}, 1},
          {%Paragraph{text: "Item B"}, 1}
        ],
        selected: 0,
        highlight_style: %Style{bg: :blue}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Item A"
    end

    test "renders with block", %{terminal: terminal} do
      wl = %WidgetList{
        items: [{%Paragraph{text: "Content"}, 1}],
        block: %Block{title: "Messages", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Messages"
      assert content =~ "Content"
    end

    test "renders empty list", %{terminal: terminal} do
      wl = %WidgetList{items: []}
      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
    end

    test "renders with scroll_offset and clips hidden items", %{terminal: terminal} do
      wl = %WidgetList{
        items: [
          {%Paragraph{text: "Hidden"}, 1},
          {%Paragraph{text: "Visible"}, 1}
        ],
        scroll_offset: 1
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Visible"
      refute content =~ "Hidden"
    end

    test "renders variable-height items", %{terminal: terminal} do
      wl = %WidgetList{
        items: [
          {%Paragraph{text: "Short"}, 1},
          {%Paragraph{text: "Tall item\nLine 2\nLine 3"}, 3},
          {%Paragraph{text: "After tall"}, 1}
        ]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Short"
      assert content =~ "Tall item"
      assert content =~ "After tall"
    end

    test "scroll_offset with selection", %{terminal: terminal} do
      wl = %WidgetList{
        items: [
          {%Paragraph{text: "Scrolled past"}, 1},
          {%Paragraph{text: "Selected item"}, 1},
          {%Paragraph{text: "Third"}, 1}
        ],
        scroll_offset: 1,
        selected: 1,
        highlight_style: %Style{bg: :blue}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Selected item"
      refute content =~ "Scrolled past"
    end

    test "renders markdown items", %{terminal: terminal} do
      wl = %WidgetList{
        items: [
          {%Markdown{content: "**Bold** text"}, 2},
          {%Markdown{content: "- item1\n- item2"}, 3}
        ]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Bold"
      assert content =~ "item1"
    end

    test "row-based scroll_offset walks through every position", %{terminal: terminal} do
      # Item 1: 3 rows ("Line 1", "Line 2", "Line 3")
      # Item 2: 2 rows ("Line 4", "Line 5")
      # Total content: 5 rows, viewport: 3 rows
      items = [
        {%Paragraph{text: "Line 1\nLine 2\nLine 3"}, 3},
        {%Paragraph{text: "Line 4\nLine 5"}, 2}
      ]

      rect = %Rect{x: 0, y: 0, width: 40, height: 3}

      # offset 0 → Lines 1, 2, 3
      wl = %WidgetList{items: items, scroll_offset: 0}
      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Line 1"
      assert content =~ "Line 2"
      assert content =~ "Line 3"
      refute content =~ "Line 4"
      refute content =~ "Line 5"

      # offset 1 → clips first row of item 1 → Lines 2, 3, 4
      wl = %WidgetList{items: items, scroll_offset: 1}
      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "Line 1"
      assert content =~ "Line 2"
      assert content =~ "Line 3"
      assert content =~ "Line 4"
      refute content =~ "Line 5"

      # offset 2 → clips two rows of item 1 → Lines 3, 4, 5
      wl = %WidgetList{items: items, scroll_offset: 2}
      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "Line 1"
      refute content =~ "Line 2"
      assert content =~ "Line 3"
      assert content =~ "Line 4"
      assert content =~ "Line 5"

      # offset 3 → item 1 fully scrolled past → Lines 4, 5 + empty
      wl = %WidgetList{items: items, scroll_offset: 3}
      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "Line 1"
      refute content =~ "Line 2"
      refute content =~ "Line 3"
      assert content =~ "Line 4"
      assert content =~ "Line 5"

      # offset 4 → clips first row of item 2 → Line 5 + empty
      wl = %WidgetList{items: items, scroll_offset: 4}
      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "Line 1"
      refute content =~ "Line 2"
      refute content =~ "Line 3"
      refute content =~ "Line 4"
      assert content =~ "Line 5"

      # offset 5 → past all content → empty
      wl = %WidgetList{items: items, scroll_offset: 5}
      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "Line 1"
      refute content =~ "Line 2"
      refute content =~ "Line 3"
      refute content =~ "Line 4"
      refute content =~ "Line 5"
    end

    test "scroll_offset past all content does not panic", %{terminal: terminal} do
      wl = %WidgetList{
        items: [
          {%Paragraph{text: "First"}, 1},
          {%Paragraph{text: "Second"}, 1}
        ],
        scroll_offset: 100
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "First"
      refute content =~ "Second"
    end

    test "scroll_offset with selection highlights correct item across clipping", %{
      terminal: terminal
    } do
      # Item 0: 2 rows, Item 1: 2 rows — scroll by 1 row so item 0 is partially
      # clipped and item 1 (selected) is fully visible
      wl = %WidgetList{
        items: [
          {%Paragraph{text: "Top\nBottom"}, 2},
          {%Paragraph{text: "Selected A\nSelected B"}, 2}
        ],
        scroll_offset: 1,
        selected: 1,
        highlight_style: %Style{bg: :blue}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{wl, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      refute content =~ "Top"
      assert content =~ "Bottom"
      assert content =~ "Selected A"
      assert content =~ "Selected B"
    end

    test "widget_list struct has correct defaults" do
      wl = %WidgetList{}
      assert wl.items == []
      assert wl.selected == nil
      assert wl.scroll_offset == 0
      assert wl.block == nil
      assert wl.style == %Style{}
      assert wl.highlight_style == %Style{}
    end
  end
end
