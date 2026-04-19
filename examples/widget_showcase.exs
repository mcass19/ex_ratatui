# Example: Widget Showcase — demonstrates Tabs, LineGauge, Scrollbar, Checkbox, TextInput, BarChart, and more.
# Run with: mix run examples/widget_showcase.exs
#
# Controls: Tab/Shift+Tab = switch tabs, Up/Down = scroll/adjust, Left/Right = select chart bar,
#           Space = toggle checkbox, q = quit

alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style

alias ExRatatui.Widgets.{
  Bar,
  BarChart,
  Block,
  Checkbox,
  LineGauge,
  Paragraph,
  Scrollbar,
  Tabs,
  TextInput
}

alias ExRatatui.Event

defmodule WidgetShowcase do
  use ExRatatui.App

  @tabs ["Progress", "Settings", "Search", "Charts", "Logs"]
  @log_lines 40

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
       traffic: [42, 67, 55, 80, 30, 72, 48],
       chart_cursor: 0,
       # Logs tab
       scroll: 0
     }}
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
    [vertical_area, horizontal_area] =
      Layout.split(area, :vertical, [{:percentage, 60}, {:percentage, 40}])

    days = ~w(Mon Tue Wed Thu Fri Sat Sun)

    vertical_bars =
      state.traffic
      |> Enum.with_index()
      |> Enum.map(fn {value, idx} ->
        selected? = idx == state.chart_cursor

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
        title: " Weekly Traffic (visits) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    horizontal_chart = %BarChart{
      data: [
        %Bar{label: "Elixir", value: 42, text_value: "42%", style: %Style{fg: :magenta}},
        %Bar{label: "Rust", value: 31, text_value: "31%", style: %Style{fg: :red}},
        %Bar{label: "Go", value: 15, text_value: "15%", style: %Style{fg: :blue}},
        %Bar{label: "Other", value: 12, text_value: "12%", style: %Style{fg: :dark_gray}}
      ],
      bar_width: 1,
      bar_gap: 0,
      value_style: %Style{fg: :white, modifiers: [:bold]},
      label_style: %Style{fg: :cyan},
      max: 100,
      direction: :horizontal,
      block: %Block{
        title: " Language Share ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    [{vertical_chart, vertical_area}, {horizontal_chart, horizontal_area}]
  end

  defp render_tab(%{tab: 4} = state, area) do
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

  defp footer_text(0), do: " Tab/Shift+Tab = switch tabs | Up/Down = adjust progress | q = quit"

  defp footer_text(1),
    do: " Tab/Shift+Tab = switch tabs | Up/Down = navigate | Space = toggle | q = quit"

  defp footer_text(2),
    do: " Tab/Shift+Tab = switch tabs | Type to search | Arrows = move cursor | q = quit"

  defp footer_text(3),
    do:
      " Tab/Shift+Tab = switch tabs | Left/Right = select bar | Up/Down = adjust value | q = quit"

  defp footer_text(4), do: " Tab/Shift+Tab = switch tabs | Up/Down = scroll | q = quit"

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

  # Charts tab: left/right selects bar, up/down adjusts value
  def handle_event(%Event.Key{code: "left", kind: "press"}, %{tab: 3} = state) do
    {:noreply, %{state | chart_cursor: max(state.chart_cursor - 1, 0)}}
  end

  def handle_event(%Event.Key{code: "right", kind: "press"}, %{tab: 3} = state) do
    max_idx = length(state.traffic) - 1
    {:noreply, %{state | chart_cursor: min(state.chart_cursor + 1, max_idx)}}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 3} = state) do
    traffic =
      Elixir.List.update_at(state.traffic, state.chart_cursor, fn v -> min(v + 5, 100) end)

    {:noreply, %{state | traffic: traffic}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 3} = state) do
    traffic =
      Elixir.List.update_at(state.traffic, state.chart_cursor, fn v -> max(v - 5, 0) end)

    {:noreply, %{state | traffic: traffic}}
  end

  # Logs tab: up/down scrolls
  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 4} = state) do
    {:noreply, %{state | scroll: min(state.scroll + 1, @log_lines - 1)}}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 4} = state) do
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
