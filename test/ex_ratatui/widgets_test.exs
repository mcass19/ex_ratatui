defmodule ExRatatui.WidgetsTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Native
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style

  alias ExRatatui.Widgets.{
    Block,
    Checkbox,
    Clear,
    Gauge,
    LineGauge,
    List,
    Paragraph,
    Scrollbar,
    Table,
    Tabs,
    TextInput,
    Markdown,
    Popup,
    Textarea,
    Throbber,
    WidgetList
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

      # First draw background
      bg = %Paragraph{text: String.duplicate("BACKGROUND ", 20)}
      assert :ok = ExRatatui.draw(terminal, [{bg, rect}])
      content_before = ExRatatui.get_buffer_content(terminal)
      assert content_before =~ "BACKGROUND"

      # Now draw popup on top
      popup = %Popup{
        content: %Paragraph{text: "Popup"},
        percent_width: 50,
        percent_height: 50
      }

      assert :ok = ExRatatui.draw(terminal, [{bg, rect}, {popup, rect}])
      content_after = ExRatatui.get_buffer_content(terminal)
      assert content_after =~ "Popup"
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

    test "throbber with different steps renders", %{terminal: terminal} do
      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      throbber0 = %Throbber{label: "Wait", step: 0}
      assert :ok = ExRatatui.draw(terminal, [{throbber0, rect}])

      throbber3 = %Throbber{label: "Wait", step: 3}
      assert :ok = ExRatatui.draw(terminal, [{throbber3, rect}])
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

      for set <- [:braille, :dots, :ascii, :vertical_block, :horizontal_block, :arrow, :clock] do
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

    test "renders with scroll_offset", %{terminal: terminal} do
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
