defmodule ExRatatui.BridgeTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Session
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph, Popup, Table, Textarea, TextInput, WidgetList}

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
               "content" => %{
                 "type" => "paragraph",
                 "text" => %{
                   "lines" => [%{"spans" => [%{"content" => "hello"}]}]
                 }
               },
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

  test "ExRatatui.encode_command/1 delegates to the shared bridge" do
    assert {
             %{
               "type" => "paragraph",
               "text" => %{
                 "lines" => [%{"spans" => [%{"content" => "delegated"}]}]
               }
             },
             %{"x" => 0, "y" => 0, "width" => 10, "height" => 2}
           } =
             ExRatatui.encode_command(
               {%Paragraph{text: "delegated"}, %Rect{x: 0, y: 0, width: 10, height: 2}}
             )
  end

  test "encode_command validates input shape and resource references" do
    rect = %Rect{x: 0, y: 0, width: 10, height: 2}

    assert_raise ArgumentError,
                 "expected a render command in the form {widget, %ExRatatui.Layout.Rect{}}, got: :bad",
                 fn ->
                   Bridge.encode_command(:bad)
                 end

    assert_raise ArgumentError,
                 "text_input.state is required and must be a reference, got: :bad",
                 fn ->
                   Bridge.encode_command({%TextInput{state: :bad}, rect})
                 end

    assert_raise ArgumentError, "textarea.state is required and must be a reference", fn ->
      Bridge.encode_command({%Textarea{}, rect})
    end

    assert_raise ArgumentError,
                 "textarea.state is required and must be a reference, got: :bad",
                 fn ->
                   Bridge.encode_command({%Textarea{state: :bad}, rect})
                 end
  end

  test "encode_command validates widgets, blocks, styles, colors, and constraints" do
    rect = %Rect{x: 0, y: 0, width: 10, height: 2}

    assert_raise ArgumentError, "unsupported widget struct: :bad", fn ->
      Bridge.encode_command({:bad, rect})
    end

    assert_raise ArgumentError,
                 "paragraph.block expected %ExRatatui.Widgets.Block{}, got: :bad",
                 fn ->
                   Bridge.encode_command({%Paragraph{text: "x", block: :bad}, rect})
                 end

    assert_raise ArgumentError, "paragraph.style expected %ExRatatui.Style{}, got: :bad", fn ->
      Bridge.encode_command({%Paragraph{text: "x", style: :bad}, rect})
    end

    assert_raise ArgumentError, "invalid color value: {:bad}", fn ->
      Bridge.encode_command({%Paragraph{text: "x", style: %Style{fg: {:bad}}}, rect})
    end

    assert_raise ArgumentError, "invalid layout constraint: {:bogus, 1}", fn ->
      Bridge.encode_command({%Table{rows: [["x"]], widths: [{:bogus, 1}]}, rect})
    end
  end

  test "encode_command accepts snapshot tuples for TextInput state (distributed path)" do
    rect = %Rect{x: 0, y: 0, width: 20, height: 1}
    snapshot = {"hello", 3, 0}
    {widget, _} = Bridge.encode_command({%TextInput{state: snapshot}, rect})

    assert widget["type"] == "text_input"
    assert widget["state"] == {"hello", 3, 0}
  end

  test "encode_command accepts snapshot tuples for Textarea state (distributed path)" do
    rect = %Rect{x: 0, y: 0, width: 20, height: 5}
    snapshot = {"line1\nline2", 1, 3}
    {widget, _} = Bridge.encode_command({%Textarea{state: snapshot}, rect})

    assert widget["type"] == "textarea"
    assert widget["state"] == {"line1\nline2", 1, 3}
  end

  test "snapshot tuple roundtrips through Session.draw without error" do
    session = Session.new(20, 5)

    widgets = [
      {%TextInput{state: {"world", 5, 0}}, %Rect{x: 0, y: 0, width: 20, height: 1}},
      {%Textarea{state: {"abc\ndef", 1, 2}}, %Rect{x: 0, y: 1, width: 20, height: 4}}
    ]

    assert :ok = Session.draw(session, widgets)
    assert byte_size(Session.take_output(session)) > 0
    Session.close(session)
  end

  test "encode_command supports min, max, and ratio constraints" do
    {widget, _rect} =
      Bridge.encode_command(
        {%Table{rows: [["x"]], widths: [{:min, 1}, {:max, 2}, {:ratio, 1, 3}]},
         %Rect{x: 0, y: 0, width: 10, height: 2}}
      )

    assert widget["widths"] == [
             %{"type" => "min", "value" => 1},
             %{"type" => "max", "value" => 2},
             %{"type" => "ratio", "num" => 1, "den" => 3}
           ]
  end
end
