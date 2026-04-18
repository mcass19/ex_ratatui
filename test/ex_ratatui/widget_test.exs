defmodule ExRatatui.WidgetTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Test.CustomWidgets.{Greeting, Stacked, TitledBox}

  describe "draw/2 with custom widgets" do
    test "renders a single-level custom widget into the test terminal" do
      terminal = ExRatatui.init_test_terminal(30, 1)
      rect = %Rect{x: 0, y: 0, width: 30, height: 1}

      assert :ok = ExRatatui.draw(terminal, [{%Greeting{name: "world"}, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "Hello, world!"
    end

    test "renders a custom widget that composes multiple primitives" do
      terminal = ExRatatui.init_test_terminal(30, 5)
      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      assert :ok =
               ExRatatui.draw(terminal, [
                 {%TitledBox{title: "Greeting", body: "hi there"}, rect}
               ])

      buffer = ExRatatui.get_buffer_content(terminal)
      assert buffer =~ "Greeting"
      assert buffer =~ "hi there"
    end

    test "recursively expands custom widgets that return other custom widgets" do
      terminal = ExRatatui.init_test_terminal(30, 4)
      rect = %Rect{x: 0, y: 0, width: 30, height: 4}

      assert :ok =
               ExRatatui.draw(terminal, [
                 {%Stacked{top_name: "friend", bottom_text: "bye"}, rect}
               ])

      buffer = ExRatatui.get_buffer_content(terminal)
      assert buffer =~ "Hello, friend!"
      assert buffer =~ "bye"
    end
  end
end
