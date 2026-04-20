defmodule ExRatatuiTest do
  use ExUnit.Case, async: true

  doctest ExRatatui
  doctest ExRatatui.Style
  doctest ExRatatui.Widgets.Paragraph
  doctest ExRatatui.Widgets.Block
  doctest ExRatatui.Widgets.List
  doctest ExRatatui.Widgets.Table
  doctest ExRatatui.Widgets.Gauge
  doctest ExRatatui.Widgets.LineGauge
  doctest ExRatatui.Widgets.BarChart
  doctest ExRatatui.Widgets.Bar
  doctest ExRatatui.Widgets.Sparkline
  doctest ExRatatui.Widgets.Calendar
  doctest ExRatatui.Widgets.Canvas
  doctest ExRatatui.Widgets.Chart
  doctest ExRatatui.Widgets.Chart.Dataset
  doctest ExRatatui.Widgets.Chart.Axis
  doctest ExRatatui.Widgets.Canvas.Line
  doctest ExRatatui.Widgets.Canvas.Rectangle
  doctest ExRatatui.Widgets.Canvas.Circle
  doctest ExRatatui.Widgets.Canvas.Points
  doctest ExRatatui.Widgets.Tabs
  doctest ExRatatui.Widgets.Scrollbar
  doctest ExRatatui.Widgets.Checkbox
  doctest ExRatatui.Widgets.Clear
  doctest ExRatatui.Widgets.TextInput
  doctest ExRatatui.Widgets.Throbber
  doctest ExRatatui.Widgets.Markdown
  doctest ExRatatui.Widgets.Textarea
  doctest ExRatatui.Widgets.Popup
  doctest ExRatatui.Widgets.WidgetList
  doctest ExRatatui.Widgets.SlashCommands
  doctest ExRatatui.Widgets.SlashCommands.Command

  test "widget structs can be created" do
    paragraph = %ExRatatui.Widgets.Paragraph{text: "Hello"}
    assert paragraph.text == "Hello"

    block = %ExRatatui.Widgets.Block{title: "Test", borders: [:all]}
    assert block.title == "Test"

    list = %ExRatatui.Widgets.List{items: ["a", "b", "c"]}
    assert length(list.items) == 3

    table = %ExRatatui.Widgets.Table{rows: [["a", "b"]], header: ["Col1", "Col2"]}
    assert length(table.rows) == 1

    gauge = %ExRatatui.Widgets.Gauge{ratio: 0.5, label: "50%"}
    assert gauge.ratio == 0.5
  end

  test "style struct has defaults" do
    style = %ExRatatui.Style{}
    assert style.fg == nil
    assert style.bg == nil
    assert style.modifiers == []
  end

  test "rect struct has defaults" do
    rect = %ExRatatui.Layout.Rect{}
    assert rect.x == 0
    assert rect.y == 0
    assert rect.width == 0
    assert rect.height == 0
  end

  test "event structs can be created" do
    key = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
    assert key.code == "q"

    mouse = %ExRatatui.Event.Mouse{kind: "down", button: "left", x: 10, y: 20}
    assert mouse.x == 10

    resize = %ExRatatui.Event.Resize{width: 80, height: 24}
    assert resize.width == 80
  end

  test "event structs have sensible defaults" do
    key = %ExRatatui.Event.Key{}
    assert key.modifiers == []
    assert key.code == nil

    mouse = %ExRatatui.Event.Mouse{}
    assert mouse.modifiers == []
    assert mouse.x == nil
  end

  describe "decode_event/1" do
    test "decodes nil (timeout)" do
      assert ExRatatui.decode_event(nil) == nil
    end

    test "decodes key event" do
      assert %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"} =
               ExRatatui.decode_event({:key, "q", [], "press"})
    end

    test "decodes mouse event" do
      assert %ExRatatui.Event.Mouse{kind: "down", button: "left", x: 10, y: 20, modifiers: []} =
               ExRatatui.decode_event({:mouse, "down", "left", 10, 20, []})
    end

    test "decodes resize event" do
      assert %ExRatatui.Event.Resize{width: 80, height: 24} =
               ExRatatui.decode_event({:resize, 80, 24})
    end

    test "passes through errors" do
      assert {:error, "test"} = ExRatatui.decode_event({:error, "test"})
    end
  end

  describe "validate_terminal_size/1" do
    test "passes through integer dimensions" do
      assert {80, 24} = ExRatatui.validate_terminal_size({80, 24})
    end

    test "passes through errors" do
      assert {:error, "no tty"} = ExRatatui.validate_terminal_size({:error, "no tty"})
    end
  end

  describe "do_run/2" do
    test "returns error when given error tuple" do
      assert {:error, "no tty"} = ExRatatui.do_run({:error, "no tty"}, fn _t -> :ok end)
    end

    test "executes function with terminal ref" do
      terminal = ExRatatui.init_test_terminal(40, 10)

      result =
        ExRatatui.do_run(terminal, fn t ->
          assert is_reference(t)
          :executed
        end)

      assert result == :executed
    end
  end

  describe "execute_with_terminal/2" do
    test "runs function and restores terminal" do
      terminal = ExRatatui.init_test_terminal(40, 10)
      result = ExRatatui.execute_with_terminal(terminal, fn _t -> :done end)
      assert result == :done
    end

    test "restores terminal even when function raises" do
      terminal = ExRatatui.init_test_terminal(40, 10)

      assert_raise RuntimeError, "boom", fn ->
        ExRatatui.execute_with_terminal(terminal, fn _t -> raise "boom" end)
      end
    end
  end

  describe "safe_restore_terminal/1" do
    test "restores a valid terminal" do
      terminal = ExRatatui.init_test_terminal(40, 10)
      assert :ok = ExRatatui.safe_restore_terminal(terminal)
    end

    @tag capture_log: true
    test "logs warning when restore fails" do
      # make_ref() is not a valid NIF resource — Native.restore_terminal raises
      ExRatatui.safe_restore_terminal(make_ref())
    end
  end
end
