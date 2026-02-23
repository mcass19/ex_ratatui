defmodule ExRatatui.TestBackendTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Native
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Gauge, List, Paragraph, Table}

  setup do
    terminal = ExRatatui.init_test_terminal(40, 10)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
  end

  describe "test terminal lifecycle" do
    test "init_test_terminal and restore" do
      terminal = ExRatatui.init_test_terminal(20, 5)
      assert :ok = Native.restore_terminal(terminal)
    end

    test "get_buffer_content returns empty buffer initially" do
      terminal = ExRatatui.init_test_terminal(10, 3)
      content = ExRatatui.get_buffer_content(terminal)
      assert is_binary(content)
      Native.restore_terminal(terminal)
    end

    test "get_buffer_content errors after terminal restored" do
      terminal = ExRatatui.init_test_terminal(10, 3)
      Native.restore_terminal(terminal)
      assert {:error, _} = ExRatatui.get_buffer_content(terminal)
    end
  end

  describe "rendering verification with TestBackend" do
    test "paragraph text appears in buffer", %{terminal: terminal} do
      paragraph = %Paragraph{text: "Hello, ExRatatui!"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "Hello, ExRatatui!"
    end

    test "paragraph with centered alignment" do
      terminal = ExRatatui.init_test_terminal(20, 3)

      paragraph = %Paragraph{text: "Hi", alignment: :center}
      rect = %Rect{x: 0, y: 0, width: 20, height: 3}

      :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      # "Hi" should be centered — not starting at column 0
      [first_line | _] = String.split(content, "\n")
      assert String.starts_with?(first_line, " ")
      assert first_line =~ "Hi"

      Native.restore_terminal(terminal)
    end

    test "multiline paragraph", %{terminal: terminal} do
      paragraph = %Paragraph{text: "Line 1\nLine 2\nLine 3"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "Line 1"
      assert content =~ "Line 2"
      assert content =~ "Line 3"
    end

    test "block with borders renders box characters", %{terminal: terminal} do
      block = %Block{borders: [:all], border_type: :plain}
      rect = %Rect{x: 0, y: 0, width: 20, height: 5}

      :ok = ExRatatui.draw(terminal, [{block, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      # Should contain box-drawing characters
      assert content =~ "┌"
      assert content =~ "┐"
      assert content =~ "└"
      assert content =~ "┘"
    end

    test "block with title", %{terminal: terminal} do
      block = %Block{title: "My Title", borders: [:all]}
      rect = %Rect{x: 0, y: 0, width: 20, height: 5}

      :ok = ExRatatui.draw(terminal, [{block, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "My Title"
    end

    test "block with rounded borders", %{terminal: terminal} do
      block = %Block{borders: [:all], border_type: :rounded}
      rect = %Rect{x: 0, y: 0, width: 20, height: 3}

      :ok = ExRatatui.draw(terminal, [{block, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "╭"
      assert content =~ "╯"
    end

    test "paragraph inside a block", %{terminal: terminal} do
      paragraph = %Paragraph{
        text: "Boxed text",
        block: %Block{title: "Box", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "Box"
      assert content =~ "Boxed text"
      assert content =~ "┌"
    end

    test "list renders items", %{terminal: terminal} do
      list = %List{items: ["Alpha", "Beta", "Gamma"]}
      rect = %Rect{x: 0, y: 0, width: 20, height: 5}

      :ok = ExRatatui.draw(terminal, [{list, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "Alpha"
      assert content =~ "Beta"
      assert content =~ "Gamma"
    end

    test "list with selection shows highlight symbol", %{terminal: terminal} do
      list = %List{
        items: ["One", "Two", "Three"],
        highlight_symbol: ">> ",
        selected: 1
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 5}

      :ok = ExRatatui.draw(terminal, [{list, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ ">>"
      assert content =~ "Two"
    end

    test "table renders rows", %{terminal: terminal} do
      table = %Table{
        rows: [["Alice", "30"], ["Bob", "25"]],
        widths: [{:length, 10}, {:length, 10}]
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "Alice"
      assert content =~ "Bob"
      assert content =~ "30"
      assert content =~ "25"
    end

    test "table with header", %{terminal: terminal} do
      table = %Table{
        rows: [["Alice", "30"]],
        header: ["Name", "Age"],
        widths: [{:length, 10}, {:length, 10}]
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "Name"
      assert content =~ "Age"
      assert content =~ "Alice"
    end

    test "gauge with label", %{terminal: terminal} do
      gauge = %Gauge{ratio: 0.5, label: "50%"}
      rect = %Rect{x: 0, y: 0, width: 20, height: 1}

      :ok = ExRatatui.draw(terminal, [{gauge, rect}])
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "50%"
    end

    test "multiple widgets in one frame", %{terminal: terminal} do
      widgets = [
        {%Paragraph{text: "Header"}, %Rect{x: 0, y: 0, width: 40, height: 1}},
        {%List{items: ["a", "b"]}, %Rect{x: 0, y: 1, width: 40, height: 3}},
        {%Gauge{ratio: 0.75, label: "75%"}, %Rect{x: 0, y: 4, width: 40, height: 1}}
      ]

      :ok = ExRatatui.draw(terminal, widgets)
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "Header"
      assert content =~ "a"
      assert content =~ "b"
      assert content =~ "75%"
    end

    test "layout split + rendering", %{terminal: terminal} do
      alias ExRatatui.Layout

      area = %Rect{x: 0, y: 0, width: 40, height: 10}
      [top, bottom] = Layout.split(area, :vertical, [{:length, 1}, {:min, 0}])

      widgets = [
        {%Paragraph{text: "Top section"}, top},
        {%Paragraph{text: "Bottom section"}, bottom}
      ]

      :ok = ExRatatui.draw(terminal, widgets)
      content = ExRatatui.get_buffer_content(terminal)

      assert content =~ "Top section"
      assert content =~ "Bottom section"
    end
  end
end
