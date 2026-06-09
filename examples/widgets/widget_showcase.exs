# Example: Widget Showcase — demonstrates Tabs, LineGauge, Scrollbar, Checkbox, TextInput,
# BarChart, Sparkline, Calendar, Canvas, Chart, and more.
# Run with: mix run examples/widget_showcase.exs
#
# Controls: Tab/Shift+Tab = switch tabs, Up/Down = scroll/adjust, Left/Right = select chart bar,
#           Space = toggle checkbox or calendar event, q = quit

alias ExRatatui.Event
alias ExRatatui.Focus
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style

alias ExRatatui.Widgets.{
  Bar,
  BarChart,
  BarGroup,
  Block,
  Calendar,
  Canvas,
  Chart,
  Checkbox,
  LineGauge,
  Paragraph,
  Scrollbar,
  Sparkline,
  Tabs,
  TextInput
}

alias ExRatatui.Widgets.Canvas.{Circle, Label, Line, Points, Rectangle}
alias ExRatatui.Widgets.Canvas.Map, as: CanvasMap
alias ExRatatui.Widgets.Chart.{Axis, Dataset}

defmodule WidgetShowcase do
  use ExRatatui.App

  @tabs ["Progress", "Settings", "Search", "Charts", "Calendar", "Canvas", "Chart", "Logs"]
  @chart_legend_positions [:top_right, :top_left, :bottom_right, :bottom_left, :top, :bottom, nil]
  @chart_markers [:braille, :dot, :block]
  @log_lines 40
  @canvas_x_bounds {0.0, 100.0}
  @canvas_y_bounds {0.0, 50.0}
  @canvas_palette [:cyan, :magenta, :yellow, :green, :red, :blue]

  @impl true
  def mount(_opts) do
    {:ok,
     %{
       tab: 0,
       # Progress tab
       download: 0.35,
       upload: 0.12,
       # Settings tab
       settings: [
         %{label: "Enable notifications", checked: true},
         %{label: "Dark mode", checked: false},
         %{label: "Auto-update", checked: true},
         %{label: "Show line numbers", checked: false},
         %{label: "Vim keybindings", checked: false}
       ],
       setting_cursor: 0,
       # Search tab
       search_input: ExRatatui.text_input_new(),
       # Charts tab
       chart_focus:
         Focus.new([:traffic, :languages, :cpu],
           next_keys: [%Event.Key{code: "]"}],
           prev_keys: [%Event.Key{code: "["}]
         ),
       traffic: [42, 67, 55, 80, 30, 72, 48],
       chart_cursor: 0,
       languages: [
         %{label: "Elixir", share: 42, fg: :magenta},
         %{label: "Rust", share: 31, fg: :red},
         %{label: "Go", share: 15, fg: :blue},
         %{label: "Other", share: 12, fg: :dark_gray}
       ],
       language_cursor: 0,
       cpu_history: [
         3,
         5,
         4,
         7,
         6,
         9,
         12,
         15,
         18,
         14,
         11,
         nil,
         8,
         6,
         10,
         13,
         17,
         20,
         18,
         15,
         12,
         10,
         9,
         7,
         nil,
         5,
         4,
         6,
         8,
         11,
         14,
         16,
         19,
         17,
         14,
         11,
         9,
         7,
         6,
         5
       ],
       # Calendar tab
       calendar_date: Date.utc_today(),
       calendar_events: seed_calendar_events(Date.utc_today()),
       # Canvas tab
       canvas_cursor: {50.0, 25.0},
       canvas_tool: :circle,
       canvas_color_index: 0,
       canvas_shapes: seed_canvas_shapes(),
       # Chart tab
       chart_cpu: seed_chart_cpu(),
       chart_mem: seed_chart_mem(),
       chart_legend_index: 0,
       chart_marker_index: 0,
       # Logs tab
       scroll: 0
     }}
  end

  defp seed_chart_cpu do
    [
      {0.0, 15.0},
      {1.0, 22.0},
      {2.0, 30.0},
      {3.0, 28.0},
      {4.0, 35.0},
      {5.0, 42.0},
      {6.0, 38.0},
      {7.0, 30.0},
      {8.0, 25.0},
      {9.0, 33.0},
      {10.0, 45.0},
      {11.0, 52.0},
      {12.0, 48.0},
      {13.0, 40.0},
      {14.0, 35.0},
      {15.0, 38.0},
      {16.0, 45.0},
      {17.0, 50.0},
      {18.0, 55.0},
      {19.0, 48.0}
    ]
  end

  defp seed_chart_mem do
    [
      {0.0, 60.0},
      {1.0, 62.0},
      {2.0, 65.0},
      {3.0, 64.0},
      {4.0, 66.0},
      {5.0, 68.0},
      {6.0, 67.0},
      {7.0, 65.0},
      {8.0, 64.0},
      {9.0, 66.0},
      {10.0, 70.0},
      {11.0, 72.0},
      {12.0, 74.0},
      {13.0, 73.0},
      {14.0, 72.0},
      {15.0, 73.0},
      {16.0, 75.0},
      {17.0, 78.0},
      {18.0, 77.0},
      {19.0, 76.0}
    ]
  end

  defp seed_canvas_shapes do
    [
      %Line{x1: 0.0, y1: 0.0, x2: 100.0, y2: 0.0, color: :dark_gray},
      %Line{x1: 0.0, y1: 0.0, x2: 0.0, y2: 50.0, color: :dark_gray},
      %Circle{x: 30.0, y: 30.0, radius: 8.0, color: :cyan},
      %Rectangle{x: 55.0, y: 10.0, width: 25.0, height: 15.0, color: :yellow},
      %Points{
        coords: [{70.0, 35.0}, {75.0, 38.0}, {80.0, 42.0}, {85.0, 40.0}],
        color: :magenta
      }
    ]
  end

  defp seed_calendar_events(today) do
    %{
      Date.add(today, -3) => %Style{fg: :green, modifiers: [:bold]},
      Date.add(today, 2) => %Style{fg: :magenta, modifiers: [:bold]},
      Date.add(today, 9) => %Style{fg: :blue, modifiers: [:bold]}
    }
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [tabs_area, body_area, footer_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 1}])

    tabs = %Tabs{
      titles: @tabs,
      selected: state.tab,
      style: %Style{fg: :dark_gray},
      highlight_style: %Style{fg: :cyan, modifiers: [:bold]},
      divider: " | ",
      block: %Block{
        title: " Widget Showcase ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    body_widgets = render_tab(state, body_area)

    footer = %Paragraph{
      text: footer_text(state.tab),
      style: %Style{fg: :dark_gray}
    }

    [{tabs, tabs_area} | body_widgets] ++ [{footer, footer_area}]
  end

  defp render_tab(%{tab: 0} = state, area) do
    [title_area, g1_area, g2_area, _spacer] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 3},
        {:length, 3},
        {:min, 0}
      ])

    title = %Paragraph{
      text: "  Transfer Progress",
      style: %Style{fg: :white, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    download = %LineGauge{
      ratio: state.download,
      label: "Download: #{round(state.download * 100)}%",
      filled_style: %Style{fg: :green},
      unfilled_style: %Style{fg: :dark_gray},
      block: %Block{borders: [:all], border_type: :rounded, border_style: %Style{fg: :dark_gray}}
    }

    upload = %LineGauge{
      ratio: state.upload,
      label: "Upload: #{round(state.upload * 100)}%",
      filled_style: %Style{fg: :blue},
      unfilled_style: %Style{fg: :dark_gray},
      block: %Block{borders: [:all], border_type: :rounded, border_style: %Style{fg: :dark_gray}}
    }

    [{title, title_area}, {download, g1_area}, {upload, g2_area}]
  end

  defp render_tab(%{tab: 1} = state, area) do
    checkboxes =
      state.settings
      |> Enum.with_index()
      |> Enum.map(fn {setting, idx} ->
        is_selected = idx == state.setting_cursor

        style =
          if is_selected,
            do: %Style{fg: :white, modifiers: [:bold]},
            else: %Style{fg: :white}

        checked_style =
          if setting.checked,
            do: %Style{fg: :green, modifiers: [:bold]},
            else: %Style{fg: :dark_gray}

        label =
          if is_selected, do: "> #{setting.label}", else: "  #{setting.label}"

        {%Checkbox{
           label: label,
           checked: setting.checked,
           style: style,
           checked_style: checked_style
         }, idx}
      end)

    height = length(state.settings)
    rows = Enum.map(0..(height - 1), fn _ -> {:length, 1} end)
    remaining = [{:min, 0}]

    layout_constraints = [{:length, 2} | rows] ++ remaining
    areas = Layout.split(area, :vertical, layout_constraints)

    header_area = Enum.at(areas, 0)

    header = %Paragraph{
      text: "  Preferences",
      style: %Style{fg: :cyan, modifiers: [:bold]}
    }

    checkbox_widgets =
      Enum.map(checkboxes, fn {cb, idx} ->
        cb_area = Enum.at(areas, idx + 1)
        {cb, cb_area}
      end)

    [{header, header_area} | checkbox_widgets]
  end

  defp render_tab(%{tab: 2} = state, area) do
    [header_area, input_area, value_area, _spacer] =
      Layout.split(area, :vertical, [
        {:length, 2},
        {:length, 3},
        {:length, 3},
        {:min, 0}
      ])

    header = %Paragraph{
      text: "  Try typing in the text input below",
      style: %Style{fg: :cyan, modifiers: [:bold]}
    }

    input = %TextInput{
      state: state.search_input,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      placeholder: "Type something...",
      placeholder_style: %Style{fg: :dark_gray},
      block: %Block{
        title: " Search ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    current_value = ExRatatui.text_input_get_value(state.search_input)
    cursor_pos = ExRatatui.text_input_cursor(state.search_input)

    value_display = %Paragraph{
      text: "  Value: \"#{current_value}\" | Cursor: #{cursor_pos}",
      style: %Style{fg: :dark_gray},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    [{header, header_area}, {input, input_area}, {value_display, value_area}]
  end

  defp render_tab(%{tab: 3} = state, area) do
    [charts_area, sparkline_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 5}])

    [vertical_area, lower_area] =
      Layout.split(charts_area, :vertical, [{:percentage, 60}, {:percentage, 40}])

    [horizontal_area, grouped_area] =
      Layout.split(lower_area, :horizontal, [{:percentage, 55}, {:percentage, 45}])

    days = ~w(Mon Tue Wed Thu Fri Sat Sun)

    vertical_bars =
      state.traffic
      |> Enum.with_index()
      |> Enum.map(fn {value, idx} ->
        selected? = Focus.focused?(state.chart_focus, :traffic) and idx == state.chart_cursor

        style =
          if selected?,
            do: %Style{fg: :yellow, modifiers: [:bold]},
            else: %Style{fg: :green}

        %Bar{label: Enum.at(days, idx), value: value, style: style}
      end)

    vertical_chart = %BarChart{
      data: vertical_bars,
      bar_width: 5,
      bar_gap: 2,
      bar_style: %Style{fg: :green},
      value_style: %Style{fg: :white, modifiers: [:bold]},
      label_style: %Style{fg: :cyan},
      max: 100,
      direction: :vertical,
      block: %Block{
        title: focus_title(" Weekly Traffic (visits) ", state.chart_focus, :traffic),
        borders: [:all],
        border_type: :rounded,
        border_style: focus_border(state.chart_focus, :traffic)
      }
    }

    horizontal_bars =
      state.languages
      |> Enum.with_index()
      |> Enum.map(fn {lang, idx} ->
        selected? = Focus.focused?(state.chart_focus, :languages) and idx == state.language_cursor

        style =
          if selected?,
            do: %Style{fg: :yellow, modifiers: [:bold]},
            else: %Style{fg: lang.fg}

        %Bar{
          label: lang.label,
          value: lang.share,
          text_value: "#{lang.share}%",
          style: style
        }
      end)

    horizontal_chart = %BarChart{
      data: horizontal_bars,
      bar_width: 1,
      bar_gap: 0,
      value_style: %Style{fg: :white, modifiers: [:bold]},
      label_style: %Style{fg: :cyan},
      max: 100,
      direction: :horizontal,
      block: %Block{
        title: focus_title(" Language Share ", state.chart_focus, :languages),
        borders: [:all],
        border_type: :rounded,
        border_style: focus_border(state.chart_focus, :languages)
      }
    }

    grouped_chart = %BarChart{
      groups: [
        %BarGroup{
          label: "Q1",
          bars: [
            %Bar{label: "EU", value: 42, style: %Style{fg: :cyan}},
            %Bar{label: "US", value: 58, style: %Style{fg: :magenta}}
          ]
        },
        %BarGroup{
          label: "Q2",
          bars: [
            %Bar{label: "EU", value: 51, style: %Style{fg: :cyan}},
            %Bar{label: "US", value: 64, style: %Style{fg: :magenta}}
          ]
        },
        %BarGroup{
          label: "Q3",
          bars: [
            %Bar{label: "EU", value: 47, style: %Style{fg: :cyan}},
            %Bar{label: "US", value: 72, style: %Style{fg: :magenta}}
          ]
        }
      ],
      bar_width: 2,
      bar_gap: 0,
      group_gap: 2,
      value_style: %Style{fg: :white, modifiers: [:bold]},
      label_style: %Style{fg: :dark_gray},
      max: 100,
      direction: :vertical,
      block: %Block{
        title: " Revenue by Region (grouped) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    sparkline = %Sparkline{
      data: state.cpu_history,
      max: 25,
      bar_set: :nine_levels,
      style: %Style{fg: :green},
      absent_value_symbol: "·",
      absent_value_style: %Style{fg: :dark_gray},
      block: %Block{
        title:
          focus_title(" CPU Load (last 40 samples · nil = missing) ", state.chart_focus, :cpu),
        borders: [:all],
        border_type: :rounded,
        border_style: focus_border(state.chart_focus, :cpu)
      }
    }

    [
      {vertical_chart, vertical_area},
      {horizontal_chart, horizontal_area},
      {grouped_chart, grouped_area},
      {sparkline, sparkline_area}
    ]
  end

  defp render_tab(%{tab: 4} = state, area) do
    [calendar_area, legend_area] =
      Layout.split(area, :horizontal, [{:length, 26}, {:min, 0}])

    cursor_style = %Style{fg: :black, bg: :yellow, modifiers: [:bold]}
    events_with_cursor = Map.put(state.calendar_events, state.calendar_date, cursor_style)

    calendar = %Calendar{
      display_date: state.calendar_date,
      events: events_with_cursor,
      default_style: %Style{fg: :white},
      header_style: %Style{fg: :cyan, modifiers: [:bold]},
      weekday_style: %Style{fg: :dark_gray, modifiers: [:bold]},
      show_surrounding: %Style{fg: :dark_gray},
      block: %Block{
        title: " #{Elixir.Calendar.strftime(state.calendar_date, "%B %Y")} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    event_dates =
      state.calendar_events
      |> Map.keys()
      |> Enum.sort(Date)
      |> Enum.map_join("\n", fn d -> "  • #{Date.to_string(d)}" end)

    cursor_line = "  Cursor: #{Date.to_string(state.calendar_date)}"

    legend_text =
      cursor_line <>
        "\n\n  Events (#{map_size(state.calendar_events)}):\n" <>
        if(event_dates == "", do: "  (none)", else: event_dates)

    legend = %Paragraph{
      text: legend_text,
      style: %Style{fg: :white},
      block: %Block{
        title: " Legend ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    [{calendar, calendar_area}, {legend, legend_area}]
  end

  defp render_tab(%{tab: 5} = state, area) do
    [canvas_column, legend_area] =
      Layout.split(area, :horizontal, [{:min, 0}, {:length, 28}])

    [canvas_area, map_area] =
      Layout.split(canvas_column, :vertical, [{:percentage, 60}, {:percentage, 40}])

    cursor_point = %Points{
      coords: [state.canvas_cursor],
      color: :white
    }

    canvas = %Canvas{
      x_bounds: @canvas_x_bounds,
      y_bounds: @canvas_y_bounds,
      marker: :braille,
      shapes: state.canvas_shapes ++ [cursor_point],
      block: %Block{
        title: " Plot (#{length(state.canvas_shapes)} shapes) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    world_map = %Canvas{
      x_bounds: {-180.0, 180.0},
      y_bounds: {-90.0, 90.0},
      marker: :dot,
      shapes: [
        %CanvasMap{resolution: :high, color: :green},
        %Label{x: -74.0, y: 40.7, text: "NYC", color: :yellow},
        %Label{x: -0.1, y: 51.5, text: "London", color: :yellow},
        %Label{x: 139.7, y: 35.7, text: "Tokyo", color: :yellow},
        %Label{x: -46.6, y: -23.5, text: "São Paulo", color: :yellow}
      ],
      block: %Block{
        title: " World Map (CanvasMap + Label) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :green}
      }
    }

    {cx, cy} = state.canvas_cursor
    color = Enum.at(@canvas_palette, state.canvas_color_index)

    legend_text = """
      Cursor: (#{:erlang.float_to_binary(cx, decimals: 1)}, #{:erlang.float_to_binary(cy, decimals: 1)})

      Tool:  #{canvas_tool_label(state.canvas_tool)}
      Color: #{color}

      1  Line
      2  Rectangle
      3  Circle
      4  Point

      Space stamps shape
      c      cycles color
      Backspace clears
    """

    legend = %Paragraph{
      text: legend_text,
      style: %Style{fg: :white},
      block: %Block{
        title: " Canvas ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    [{canvas, canvas_area}, {world_map, map_area}, {legend, legend_area}]
  end

  defp render_tab(%{tab: 6} = state, area) do
    legend_position = Enum.at(@chart_legend_positions, state.chart_legend_index)
    marker = Enum.at(@chart_markers, state.chart_marker_index)

    legend_label =
      case legend_position do
        nil -> "hidden"
        pos -> Atom.to_string(pos)
      end

    chart = %Chart{
      datasets: [
        %Dataset{
          name: "CPU %",
          data: state.chart_cpu,
          marker: marker,
          graph_type: :line,
          style: %Style{fg: :cyan}
        },
        %Dataset{
          name: "Memory %",
          data: state.chart_mem,
          marker: marker,
          graph_type: :line,
          style: %Style{fg: :magenta}
        }
      ],
      x_axis: %Axis{
        title: "Sample",
        bounds: {0.0, 19.0},
        labels: ["0", "5", "10", "15", "19"],
        style: %Style{fg: :dark_gray}
      },
      y_axis: %Axis{
        title: "Usage %",
        bounds: {0.0, 100.0},
        labels: ["0", "50", "100"],
        style: %Style{fg: :dark_gray}
      },
      legend_position: legend_position,
      hidden_legend_constraints: {{:ratio, 1, 4}, {:ratio, 1, 4}},
      block: %Block{
        title: " Metrics — legend: #{legend_label} · marker: #{marker} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    [{chart, area}]
  end

  defp render_tab(%{tab: 7} = state, %Rect{} = area) do
    content_width = area.width - 1
    content_area = %Rect{area | width: content_width}
    scrollbar_area = %Rect{area | x: area.x + content_width, width: 1}

    visible_lines = area.height - 2

    text =
      Enum.map_join(0..(@log_lines - 1), "\n", fn i ->
        level = Enum.at(["INFO ", "DEBUG", "WARN ", "ERROR"], rem(i, 4))

        "  [#{level}] 2026-03-22 12:#{String.pad_leading("#{rem(i, 60)}", 2, "0")}:00 — Event ##{i + 1} processed"
      end)

    content = %Paragraph{
      text: text,
      style: %Style{fg: :white},
      scroll: {state.scroll, 0},
      block: %Block{
        title: " Application Logs (#{state.scroll + 1}/#{@log_lines}) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    scrollbar = %Scrollbar{
      content_length: @log_lines,
      position: state.scroll,
      viewport_content_length: visible_lines,
      thumb_style: %Style{fg: :cyan},
      track_style: %Style{fg: :dark_gray}
    }

    [{content, content_area}, {scrollbar, scrollbar_area}]
  end

  defp bump_chart_sample(points, delta) do
    Elixir.List.update_at(points, -1, fn {x, y} ->
      {x, clamp(y + delta, 0.0, 100.0)}
    end)
  end

  defp canvas_tool_label(:line), do: "Line"
  defp canvas_tool_label(:rectangle), do: "Rectangle"
  defp canvas_tool_label(:circle), do: "Circle"
  defp canvas_tool_label(:point), do: "Point"

  defp handle_chart_key(%Event.Key{code: "left"}, :traffic, state) do
    %{state | chart_cursor: max(state.chart_cursor - 1, 0)}
  end

  defp handle_chart_key(%Event.Key{code: "right"}, :traffic, state) do
    max_idx = length(state.traffic) - 1
    %{state | chart_cursor: min(state.chart_cursor + 1, max_idx)}
  end

  defp handle_chart_key(%Event.Key{code: "up"}, :traffic, state) do
    traffic =
      Elixir.List.update_at(state.traffic, state.chart_cursor, fn v -> min(v + 5, 100) end)

    %{state | traffic: traffic}
  end

  defp handle_chart_key(%Event.Key{code: "down"}, :traffic, state) do
    traffic =
      Elixir.List.update_at(state.traffic, state.chart_cursor, fn v -> max(v - 5, 0) end)

    %{state | traffic: traffic}
  end

  defp handle_chart_key(%Event.Key{code: "up"}, :languages, state) do
    %{state | language_cursor: max(state.language_cursor - 1, 0)}
  end

  defp handle_chart_key(%Event.Key{code: "down"}, :languages, state) do
    max_idx = length(state.languages) - 1
    %{state | language_cursor: min(state.language_cursor + 1, max_idx)}
  end

  defp handle_chart_key(%Event.Key{code: "left"}, :languages, state) do
    languages =
      Elixir.List.update_at(state.languages, state.language_cursor, fn l ->
        %{l | share: max(l.share - 5, 0)}
      end)

    %{state | languages: languages}
  end

  defp handle_chart_key(%Event.Key{code: "right"}, :languages, state) do
    languages =
      Elixir.List.update_at(state.languages, state.language_cursor, fn l ->
        %{l | share: min(l.share + 5, 100)}
      end)

    %{state | languages: languages}
  end

  defp handle_chart_key(%Event.Key{code: "up"}, :cpu, state) do
    push_cpu_sample(state, last_cpu_value(state) + 3)
  end

  defp handle_chart_key(%Event.Key{code: "down"}, :cpu, state) do
    push_cpu_sample(state, max(last_cpu_value(state) - 3, 0))
  end

  defp handle_chart_key(%Event.Key{code: " "}, :cpu, state) do
    push_cpu_sample(state, nil)
  end

  defp handle_chart_key(_key, _focus, state), do: state

  defp last_cpu_value(state) do
    state.cpu_history
    |> Enum.reverse()
    |> Enum.find(&is_integer/1)
    |> Kernel.||(0)
  end

  defp push_cpu_sample(state, sample) do
    [_oldest | rest] = state.cpu_history
    %{state | cpu_history: rest ++ [sample]}
  end

  defp move_canvas_cursor({x, y}, dx, dy) do
    {min_x, max_x} = @canvas_x_bounds
    {min_y, max_y} = @canvas_y_bounds
    {clamp(x + dx, min_x, max_x), clamp(y + dy, min_y, max_y)}
  end

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value

  defp stamp_canvas_shape(%{canvas_tool: :line, canvas_cursor: {x, y}} = state) do
    %Line{x1: x, y1: y, x2: x + 15.0, y2: y + 10.0, color: canvas_color(state)}
  end

  defp stamp_canvas_shape(%{canvas_tool: :rectangle, canvas_cursor: {x, y}} = state) do
    %Rectangle{x: x, y: y, width: 10.0, height: 8.0, color: canvas_color(state)}
  end

  defp stamp_canvas_shape(%{canvas_tool: :circle, canvas_cursor: {x, y}} = state) do
    %Circle{x: x, y: y, radius: 5.0, color: canvas_color(state)}
  end

  defp stamp_canvas_shape(%{canvas_tool: :point, canvas_cursor: {x, y}} = state) do
    %Points{coords: [{x, y}], color: canvas_color(state)}
  end

  defp canvas_color(state), do: Enum.at(@canvas_palette, state.canvas_color_index)

  defp focus_border(focus, id) do
    if Focus.focused?(focus, id),
      do: %Style{fg: :yellow, modifiers: [:bold]},
      else: %Style{fg: :dark_gray}
  end

  defp focus_title(title, focus, id) do
    if Focus.focused?(focus, id), do: "●" <> title, else: title
  end

  defp footer_text(0), do: " Tab/Shift+Tab = switch tabs | Up/Down = adjust progress | q = quit"

  defp footer_text(1),
    do: " Tab/Shift+Tab = switch tabs | Up/Down = navigate | Space = toggle | q = quit"

  defp footer_text(2),
    do: " Tab/Shift+Tab = switch tabs | Type to search | Arrows = move cursor | q = quit"

  defp footer_text(3),
    do:
      " Tab = tabs | [ / ] = cycle focus | arrows = interact with focused chart | Space = push gap (CPU) | q = quit"

  defp footer_text(4),
    do:
      " Tab/Shift+Tab = switch tabs | arrows = move cursor (±1 / ±7 days) | Space = toggle event | q = quit"

  defp footer_text(5),
    do:
      " Tab = tabs | arrows = move cursor | 1-4 = tool | c = color | Space = stamp | Backspace = clear | q = quit"

  defp footer_text(6),
    do:
      " Tab/Shift+Tab = switch tabs | Up/Down = adjust last CPU sample | L = cycle legend | M = cycle marker | q = quit"

  defp footer_text(7), do: " Tab/Shift+Tab = switch tabs | Up/Down = scroll | q = quit"

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  # Global tab switching
  def handle_event(%Event.Key{code: "tab", kind: "press"}, state) do
    {:noreply, %{state | tab: rem(state.tab + 1, length(@tabs))}}
  end

  def handle_event(%Event.Key{code: "back_tab", kind: "press"}, state) do
    {:noreply, %{state | tab: rem(state.tab - 1 + length(@tabs), length(@tabs))}}
  end

  # Search tab: forward all other keys to text input
  def handle_event(%Event.Key{code: code, kind: "press"}, %{tab: 2} = state) do
    ExRatatui.text_input_handle_key(state.search_input, code)
    {:noreply, state}
  end

  # Progress tab: up/down adjusts gauge
  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 0} = state) do
    {:noreply,
     %{
       state
       | download: min(state.download + 0.05, 1.0),
         upload: min(state.upload + 0.03, 1.0)
     }}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 0} = state) do
    {:noreply,
     %{
       state
       | download: max(state.download - 0.05, 0.0),
         upload: max(state.upload - 0.03, 0.0)
     }}
  end

  # Settings tab: up/down navigates, space toggles
  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 1} = state) do
    {:noreply, %{state | setting_cursor: max(state.setting_cursor - 1, 0)}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 1} = state) do
    max_idx = length(state.settings) - 1
    {:noreply, %{state | setting_cursor: min(state.setting_cursor + 1, max_idx)}}
  end

  def handle_event(%Event.Key{code: " ", kind: "press"}, %{tab: 1} = state) do
    settings =
      Elixir.List.update_at(state.settings, state.setting_cursor, fn s ->
        %{s | checked: !s.checked}
      end)

    {:noreply, %{state | settings: settings}}
  end

  # Charts tab: [ / ] cycle focus, arrows interact with focused chart.
  def handle_event(%Event.Key{kind: "press"} = key, %{tab: 3} = state) do
    {focus, key} = Focus.handle_key(state.chart_focus, key)
    state = %{state | chart_focus: focus}

    case key do
      nil -> {:noreply, state}
      key -> {:noreply, handle_chart_key(key, Focus.current(focus), state)}
    end
  end

  # Calendar tab: arrows move the cursor, Space toggles an event
  def handle_event(%Event.Key{code: "left", kind: "press"}, %{tab: 4} = state) do
    {:noreply, %{state | calendar_date: Date.add(state.calendar_date, -1)}}
  end

  def handle_event(%Event.Key{code: "right", kind: "press"}, %{tab: 4} = state) do
    {:noreply, %{state | calendar_date: Date.add(state.calendar_date, 1)}}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 4} = state) do
    {:noreply, %{state | calendar_date: Date.add(state.calendar_date, -7)}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 4} = state) do
    {:noreply, %{state | calendar_date: Date.add(state.calendar_date, 7)}}
  end

  def handle_event(%Event.Key{code: " ", kind: "press"}, %{tab: 4} = state) do
    events =
      Map.update(
        state.calendar_events,
        state.calendar_date,
        %Style{fg: :magenta, modifiers: [:bold]},
        fn _existing -> nil end
      )

    {:noreply, %{state | calendar_events: events}}
  end

  # Canvas tab: arrows move cursor, 1-4 select tool, c cycles color,
  # Space stamps the current tool at the cursor, Backspace clears user shapes.
  def handle_event(%Event.Key{code: "left", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_cursor: move_canvas_cursor(state.canvas_cursor, -2.0, 0.0)}}
  end

  def handle_event(%Event.Key{code: "right", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_cursor: move_canvas_cursor(state.canvas_cursor, 2.0, 0.0)}}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_cursor: move_canvas_cursor(state.canvas_cursor, 0.0, 2.0)}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_cursor: move_canvas_cursor(state.canvas_cursor, 0.0, -2.0)}}
  end

  def handle_event(%Event.Key{code: "1", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_tool: :line}}
  end

  def handle_event(%Event.Key{code: "2", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_tool: :rectangle}}
  end

  def handle_event(%Event.Key{code: "3", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_tool: :circle}}
  end

  def handle_event(%Event.Key{code: "4", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_tool: :point}}
  end

  def handle_event(%Event.Key{code: "c", kind: "press"}, %{tab: 5} = state) do
    next = rem(state.canvas_color_index + 1, length(@canvas_palette))
    {:noreply, %{state | canvas_color_index: next}}
  end

  def handle_event(%Event.Key{code: " ", kind: "press"}, %{tab: 5} = state) do
    shape = stamp_canvas_shape(state)
    {:noreply, %{state | canvas_shapes: state.canvas_shapes ++ [shape]}}
  end

  def handle_event(%Event.Key{code: "backspace", kind: "press"}, %{tab: 5} = state) do
    {:noreply, %{state | canvas_shapes: seed_canvas_shapes()}}
  end

  # Chart tab: Up/Down adjust last CPU sample, L cycles legend, M cycles marker.
  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 6} = state) do
    {:noreply, %{state | chart_cpu: bump_chart_sample(state.chart_cpu, +5.0)}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 6} = state) do
    {:noreply, %{state | chart_cpu: bump_chart_sample(state.chart_cpu, -5.0)}}
  end

  def handle_event(%Event.Key{code: "l", kind: "press"}, %{tab: 6} = state) do
    next = rem(state.chart_legend_index + 1, length(@chart_legend_positions))
    {:noreply, %{state | chart_legend_index: next}}
  end

  def handle_event(%Event.Key{code: "m", kind: "press"}, %{tab: 6} = state) do
    next = rem(state.chart_marker_index + 1, length(@chart_markers))
    {:noreply, %{state | chart_marker_index: next}}
  end

  # Logs tab: up/down scrolls
  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 7} = state) do
    {:noreply, %{state | scroll: min(state.scroll + 1, @log_lines - 1)}}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 7} = state) do
    {:noreply, %{state | scroll: max(state.scroll - 1, 0)}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end

{:ok, pid} = WidgetShowcase.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
