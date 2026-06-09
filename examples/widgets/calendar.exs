# Example: Calendar — a month view with styled events and a movable cursor.
# Run with: mix run examples/widgets/calendar.exs
#
# Controls: Left/Right = +/- 1 day, Up/Down = +/- 1 week,
#           Space = toggle an event on the cursor date, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Calendar, Paragraph}

defmodule CalendarDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts) do
    today = Date.utc_today()

    {:ok,
     %{
       date: today,
       events: %{
         Date.add(today, -3) => %Style{fg: :green, modifiers: [:bold]},
         Date.add(today, 2) => %Style{fg: :magenta, modifiers: [:bold]},
         Date.add(today, 9) => %Style{fg: :blue, modifiers: [:bold]}
       }
     }}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [calendar_area, legend_area] =
      Layout.split(area, :horizontal, [{:length, 26}, {:min, 0}])

    cursor_style = %Style{fg: :black, bg: :yellow, modifiers: [:bold]}
    events_with_cursor = Map.put(state.events, state.date, cursor_style)

    calendar = %Calendar{
      display_date: state.date,
      events: events_with_cursor,
      default_style: %Style{fg: :white},
      header_style: %Style{fg: :cyan, modifiers: [:bold]},
      weekday_style: %Style{fg: :dark_gray, modifiers: [:bold]},
      show_surrounding: %Style{fg: :dark_gray},
      block: %Block{
        title: " #{Elixir.Calendar.strftime(state.date, "%B %Y")} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    [{calendar, calendar_area}, {legend(state), legend_area}]
  end

  defp legend(state) do
    dates =
      state.events
      |> Map.keys()
      |> Enum.sort(Date)
      |> Enum.map_join("\n", fn d -> "  • #{Date.to_string(d)}" end)

    text =
      "  Cursor: #{Date.to_string(state.date)}\n\n" <>
        "  Events (#{map_size(state.events)}):\n" <>
        if(dates == "", do: "  (none)", else: dates) <>
        "\n\n  Left/Right = day   Up/Down = week\n  Space = toggle event   q = quit"

    %Paragraph{
      text: text,
      style: %Style{fg: :white},
      block: %Block{
        title: " Legend ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: "right", kind: "press"}, state),
    do: {:noreply, %{state | date: Date.add(state.date, 1)}}

  def handle_event(%Event.Key{code: "left", kind: "press"}, state),
    do: {:noreply, %{state | date: Date.add(state.date, -1)}}

  def handle_event(%Event.Key{code: "down", kind: "press"}, state),
    do: {:noreply, %{state | date: Date.add(state.date, 7)}}

  def handle_event(%Event.Key{code: "up", kind: "press"}, state),
    do: {:noreply, %{state | date: Date.add(state.date, -7)}}

  def handle_event(%Event.Key{code: " ", kind: "press"}, state) do
    events =
      if Map.has_key?(state.events, state.date) do
        Map.delete(state.events, state.date)
      else
        Map.put(state.events, state.date, %Style{fg: :yellow, modifiers: [:bold]})
      end

    {:noreply, %{state | events: events}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = CalendarDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
