defmodule ExRatatui.Widgets.ParagraphTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  setup do
    terminal = ExRatatui.init_test_terminal(60, 15)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
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

    test "underline_color renders without error", %{terminal: terminal} do
      paragraph = %Paragraph{
        text: "colored underline",
        style: %Style{modifiers: [:underlined], underline_color: {:rgb, 255, 0, 0}}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "colored underline"
    end
  end
end
