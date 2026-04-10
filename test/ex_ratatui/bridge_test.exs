defmodule ExRatatui.BridgeTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Session
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph, Popup, TextInput, WidgetList}

  test "encode_command encodes nested widgets through the shared bridge" do
    command =
      Bridge.encode_command(
        {%Popup{
           content: %Paragraph{
             text: "hello",
             style: %Style{fg: :green},
             block: %Block{title: "Inner", borders: [:all]}
           },
           block: %Block{title: "Outer", borders: [:all]},
           fixed_width: 20,
           fixed_height: 5
         }, %Rect{x: 1, y: 2, width: 30, height: 10}}
      )

    assert {
             %{
               "type" => "popup",
               "content" => %{"type" => "paragraph", "text" => "hello"},
               "fixed_width" => 20,
               "fixed_height" => 5
             },
             %{"x" => 1, "y" => 2, "width" => 30, "height" => 10}
           } = command
  end

  test "draw raises a contextual validation error for text input without state" do
    terminal = ExRatatui.init_test_terminal(20, 5)
    on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

    assert_raise ArgumentError, "text_input.state is required and must be a reference", fn ->
      ExRatatui.draw(terminal, [{%TextInput{}, %Rect{x: 0, y: 0, width: 20, height: 1}}])
    end
  end

  test "session draw uses the same validation path" do
    session = Session.new(20, 5)
    on_exit(fn -> Session.close(session) end)

    assert_raise ArgumentError,
                 "widget_list.items must contain {widget, non_neg_integer()} tuples, got: {\"bad\", :height}",
                 fn ->
                   Session.draw(session, [
                     {%WidgetList{items: [{"bad", :height}]},
                      %Rect{x: 0, y: 0, width: 20, height: 5}}
                   ])
                 end
  end
end
