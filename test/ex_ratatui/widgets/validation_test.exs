defmodule ExRatatui.Widgets.ValidationTest do
  @moduledoc """
  Cross-widget validation tests covering struct defaults and the
  ArgumentError contract at the Bridge encoding boundary. Lives here
  (not alongside individual widget tests) because it exercises the
  uniform rejection shape across every widget type in one place.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native

  alias ExRatatui.Widgets.{
    Bar,
    BarChart,
    BarGroup,
    Block,
    Calendar,
    Canvas,
    Checkbox,
    Gauge,
    LineGauge,
    List,
    Scrollbar,
    Sparkline,
    Table,
    Tabs
  }

  alias ExRatatui.Widgets.Canvas.{Circle, Label, Line, Points, Rectangle}
  alias ExRatatui.Widgets.Canvas.Map, as: CanvasMap

  setup do
    terminal = ExRatatui.init_test_terminal(60, 15)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
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
      assert chart.groups == []
      assert chart.bar_width == 1
      assert chart.bar_gap == 1
      assert chart.group_gap == 0
      assert chart.max == nil
      assert chart.direction == :vertical
      assert chart.block == nil
    end

    test "bar_group struct has correct defaults" do
      group = %BarGroup{}
      assert group.label == nil
      assert group.bars == []
    end

    test "bar_chart encodes :data as a single anonymous group", %{terminal: terminal} do
      chart = %BarChart{data: [%Bar{label: "Elixir", value: 80}]}
      rect = %Rect{x: 0, y: 0, width: 30, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
    end

    test "bar_chart accepts a BarGroup with nil label (label key omitted)", %{
      terminal: terminal
    } do
      chart = %BarChart{
        groups: [%BarGroup{label: nil, bars: [%Bar{label: "A", value: 10}]}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
    end

    test "bar_chart renders explicit groups with labels", %{terminal: terminal} do
      chart = %BarChart{
        groups: [
          %BarGroup{
            label: "Q1",
            bars: [%Bar{label: "A", value: 10}, %Bar{label: "B", value: 20}]
          },
          %BarGroup{
            label: "Q2",
            bars: [%Bar{label: "A", value: 15}, %Bar{label: "B", value: 25}]
          }
        ],
        bar_width: 3,
        bar_gap: 1,
        group_gap: 3,
        max: 30
      }

      rect = %Rect{x: 0, y: 0, width: 50, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{chart, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Q1"
      assert content =~ "Q2"
    end

    test "bar_chart rejects non-list :groups" do
      chart = %BarChart{groups: "not a list"}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/list of %BarGroup\{\}/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
    end

    test "bar_chart rejects non-BarGroup entry in :groups" do
      chart = %BarChart{groups: [{:not_a_group}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/entries to be %BarGroup\{\}/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
    end

    test "bar_chart rejects non-string group label" do
      chart = %BarChart{groups: [%BarGroup{label: 123, bars: []}]}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/label expected a string or nil/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
    end

    test "bar_chart rejects negative group_gap" do
      chart = %BarChart{group_gap: -1}
      rect = %Rect{x: 0, y: 0, width: 10, height: 4}

      assert_raise ArgumentError, ~r/group_gap expected a non-negative integer/, fn ->
        ExRatatui.Bridge.encode_commands!([{chart, rect}])
      end
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

    test "gauge accepts integer ratio 0 and 1", %{terminal: terminal} do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}
      assert :ok = ExRatatui.draw(terminal, [{%Gauge{ratio: 0}, rect}])
      assert :ok = ExRatatui.draw(terminal, [{%Gauge{ratio: 1}, rect}])
    end

    test "gauge rejects ratio above 1.0" do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/gauge\.ratio expected a number in 0\.0\.\.1\.0/, fn ->
        ExRatatui.Bridge.encode_commands!([{%Gauge{ratio: 1.5}, rect}])
      end
    end

    test "gauge rejects negative ratio" do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/gauge\.ratio expected a number in 0\.0\.\.1\.0/, fn ->
        ExRatatui.Bridge.encode_commands!([{%Gauge{ratio: -0.1}, rect}])
      end
    end

    test "gauge rejects non-numeric ratio" do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/gauge\.ratio expected a number in 0\.0\.\.1\.0/, fn ->
        ExRatatui.Bridge.encode_commands!([{%Gauge{ratio: "half"}, rect}])
      end
    end

    test "line_gauge accepts integer ratio 0 and 1", %{terminal: terminal} do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}
      assert :ok = ExRatatui.draw(terminal, [{%LineGauge{ratio: 0}, rect}])
      assert :ok = ExRatatui.draw(terminal, [{%LineGauge{ratio: 1}, rect}])
    end

    test "line_gauge rejects ratio above 1.0" do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/line_gauge\.ratio expected a number in 0\.0\.\.1\.0/, fn ->
        ExRatatui.Bridge.encode_commands!([{%LineGauge{ratio: 2.0}, rect}])
      end
    end

    test "line_gauge rejects negative ratio" do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/line_gauge\.ratio expected a number in 0\.0\.\.1\.0/, fn ->
        ExRatatui.Bridge.encode_commands!([{%LineGauge{ratio: -0.5}, rect}])
      end
    end

    test "line_gauge rejects non-numeric ratio" do
      rect = %Rect{x: 0, y: 0, width: 10, height: 1}

      assert_raise ArgumentError, ~r/line_gauge\.ratio expected a number in 0\.0\.\.1\.0/, fn ->
        ExRatatui.Bridge.encode_commands!([{%LineGauge{ratio: :full}, rect}])
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

    test "canvas renders a Map shape with low resolution", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {-180.0, 180.0},
        y_bounds: {-90.0, 90.0},
        marker: :dot,
        shapes: [%CanvasMap{resolution: :low, color: :green}]
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 14}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
    end

    test "canvas renders a Label shape", %{terminal: terminal} do
      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Label{x: 1.0, y: 5.0, text: "origin", color: :white}]
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{canvas, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "origin"
    end

    test "canvas rejects Map with missing color" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {-180.0, 180.0},
        y_bounds: {-90.0, 90.0},
        shapes: [%CanvasMap{resolution: :low}]
      }

      assert_raise ArgumentError, ~r/Map\.color is required/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Map with unknown resolution" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {-180.0, 180.0},
        y_bounds: {-90.0, 90.0},
        shapes: [%CanvasMap{resolution: :medium, color: :green}]
      }

      assert_raise ArgumentError, ~r/Map\.resolution expected :low or :high/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Label with missing text" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Label{x: 1.0, y: 1.0, color: :white}]
      }

      assert_raise ArgumentError, ~r/Label\.text is required/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Label with non-string text" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Label{x: 1.0, y: 1.0, text: 42, color: :white}]
      }

      assert_raise ArgumentError, ~r/Label\.text expected a string/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Label with missing x" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Label{y: 1.0, text: "x", color: :white}]
      }

      assert_raise ArgumentError, ~r/Label\.x is required/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Label with missing y" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Label{x: 1.0, text: "x", color: :white}]
      }

      assert_raise ArgumentError, ~r/Label\.y is required/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end

    test "canvas rejects Label with missing color" do
      rect = %Rect{x: 0, y: 0, width: 20, height: 10}

      canvas = %Canvas{
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        shapes: [%Label{x: 1.0, y: 1.0, text: "x"}]
      }

      assert_raise ArgumentError, ~r/Label\.color is required/, fn ->
        ExRatatui.Bridge.encode_commands!([{canvas, rect}])
      end
    end
  end
end
