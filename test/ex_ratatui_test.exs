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
  doctest ExRatatui.Widgets.Tabs
  doctest ExRatatui.Widgets.Scrollbar
  doctest ExRatatui.Widgets.Checkbox

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
end
