# Example: BarChart — vertical, horizontal, and grouped bar charts.
# Run with: mix run examples/widgets/barchart.exs
#
# Controls: Left/Right = highlight a bar in the weekly chart, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Bar, BarChart, BarGroup, Block, Paragraph}

defmodule BarChartDemo do
  use ExRatatui.App

  @days ~w(Mon Tue Wed Thu Fri Sat Sun)
  @traffic [42, 67, 55, 80, 30, 72, 48]

  @languages [
    %{label: "Elixir", share: 42, fg: :magenta},
    %{label: "Rust", share: 31, fg: :red},
    %{label: "Go", share: 15, fg: :blue},
    %{label: "Other", share: 12, fg: :dark_gray}
  ]

  @impl true
  def mount(_opts), do: {:ok, %{cursor: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [top_area, lower_area, help_area] =
      Layout.split(area, :vertical, [{:percentage, 55}, {:min, 0}, {:length, 3}])

    [horizontal_area, grouped_area] =
      Layout.split(lower_area, :horizontal, [{:percentage, 55}, {:percentage, 45}])

    [
      {vertical_chart(state), top_area},
      {horizontal_chart(), horizontal_area},
      {grouped_chart(), grouped_area},
      {help(), help_area}
    ]
  end

  defp vertical_chart(state) do
    bars =
      @traffic
      |> Enum.with_index()
      |> Enum.map(fn {value, idx} ->
        style =
          if idx == state.cursor,
            do: %Style{fg: :yellow, modifiers: [:bold]},
            else: %Style{fg: :green}

        %Bar{label: Enum.at(@days, idx), value: value, style: style}
      end)

    %BarChart{
      data: bars,
      bar_width: 5,
      bar_gap: 2,
      value_style: %Style{fg: :white, modifiers: [:bold]},
      label_style: %Style{fg: :cyan},
      max: 100,
      direction: :vertical,
      block: block(" Weekly Traffic (visits) ", :green)
    }
  end

  defp horizontal_chart do
    bars =
      Enum.map(@languages, fn lang ->
        %Bar{
          label: lang.label,
          value: lang.share,
          text_value: "#{lang.share}%",
          style: %Style{fg: lang.fg}
        }
      end)

    %BarChart{
      data: bars,
      bar_width: 1,
      bar_gap: 0,
      value_style: %Style{fg: :white, modifiers: [:bold]},
      label_style: %Style{fg: :cyan},
      max: 100,
      direction: :horizontal,
      block: block(" Language Share ", :cyan)
    }
  end

  defp grouped_chart do
    %BarChart{
      groups: [
        group("Q1", 42, 58),
        group("Q2", 51, 64),
        group("Q3", 47, 72)
      ],
      bar_width: 2,
      bar_gap: 0,
      group_gap: 2,
      value_style: %Style{fg: :white, modifiers: [:bold]},
      label_style: %Style{fg: :dark_gray},
      max: 100,
      direction: :vertical,
      block: block(" Revenue by Region (grouped) ", :dark_gray)
    }
  end

  defp group(label, eu, us) do
    %BarGroup{
      label: label,
      bars: [
        %Bar{label: "EU", value: eu, style: %Style{fg: :cyan}},
        %Bar{label: "US", value: us, style: %Style{fg: :magenta}}
      ]
    }
  end

  defp block(title, fg) do
    %Block{title: title, borders: [:all], border_type: :rounded, border_style: %Style{fg: fg}}
  end

  defp help do
    %Paragraph{
      text: "  Left/Right = highlight a weekday bar   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["Right", "l"] do
    {:noreply, %{state | cursor: rem(state.cursor + 1, length(@traffic))}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["Left", "h"] do
    {:noreply, %{state | cursor: rem(state.cursor - 1 + length(@traffic), length(@traffic))}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = BarChartDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
