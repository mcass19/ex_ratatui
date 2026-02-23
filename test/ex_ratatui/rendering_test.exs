defmodule ExRatatui.RenderingTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Native
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  setup do
    terminal = ExRatatui.init_test_terminal(40, 10)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
  end

  describe "draw/2" do
    test "returns error when terminal not initialized" do
      terminal = ExRatatui.init_test_terminal(40, 10)
      Native.restore_terminal(terminal)

      paragraph = %Paragraph{text: "Hello"}
      rect = %Rect{x: 0, y: 0, width: 80, height: 24}

      result = ExRatatui.draw(terminal, [{paragraph, rect}])
      assert {:error, "terminal not initialized"} = result
    end

    test "accepts paragraph with default style", %{terminal: terminal} do
      paragraph = %Paragraph{text: "Hello, world!"}
      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "Hello, world!"
    end

    test "accepts paragraph with styled text", %{terminal: terminal} do
      paragraph = %Paragraph{
        text: "Styled text",
        style: %Style{fg: :green, bg: :black, modifiers: [:bold]},
        alignment: :center,
        wrap: true
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "Styled text"
    end

    test "accepts paragraph with RGB color", %{terminal: terminal} do
      paragraph = %Paragraph{
        text: "RGB colored",
        style: %Style{fg: {:rgb, 255, 100, 0}}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{paragraph, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "RGB colored"
    end

    test "accepts multiple widgets in one frame", %{terminal: terminal} do
      widgets = [
        {%Paragraph{text: "Top"}, %Rect{x: 0, y: 0, width: 40, height: 3}},
        {%Paragraph{text: "Bottom"}, %Rect{x: 0, y: 3, width: 40, height: 3}}
      ]

      assert :ok = ExRatatui.draw(terminal, widgets)
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Top"
      assert content =~ "Bottom"
    end

    test "accepts empty widget list", %{terminal: terminal} do
      assert :ok = ExRatatui.draw(terminal, [])
    end
  end
end
