# Example: Widget Showcase — demonstrates Tabs, LineGauge, Scrollbar, Checkbox, and more.
# Run with: EX_RATATUI_BUILD=true mix run examples/widget_showcase.exs
#
# Controls: Left/Right = switch tabs, Up/Down = scroll/adjust, Space = toggle checkbox, q = quit

alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Checkbox, LineGauge, List, Paragraph, Scrollbar, Tabs}
alias ExRatatui.Event

defmodule WidgetShowcase do
  use ExRatatui.App

  @tabs ["Progress", "Settings", "Logs"]
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

  defp footer_text(0), do: " Left/Right = tabs | Up/Down = adjust progress | q = quit"
  defp footer_text(1), do: " Left/Right = tabs | Up/Down = navigate | Space = toggle | q = quit"
  defp footer_text(2), do: " Left/Right = tabs | Up/Down = scroll | q = quit"

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "right", kind: "press"}, state) do
    {:noreply, %{state | tab: rem(state.tab + 1, length(@tabs))}}
  end

  def handle_event(%Event.Key{code: "left", kind: "press"}, state) do
    {:noreply, %{state | tab: rem(state.tab - 1 + length(@tabs), length(@tabs))}}
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

  # Logs tab: up/down scrolls
  def handle_event(%Event.Key{code: "down", kind: "press"}, %{tab: 2} = state) do
    {:noreply, %{state | scroll: min(state.scroll + 1, @log_lines - 1)}}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, %{tab: 2} = state) do
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
