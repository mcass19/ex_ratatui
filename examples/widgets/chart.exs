# Example: Chart — line datasets with x/y axes and a configurable legend.
# Run with: mix run examples/widgets/chart.exs
#
# Controls: l = cycle legend position, m = cycle marker, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Chart, Paragraph}
alias ExRatatui.Widgets.Chart.{Axis, Dataset}

defmodule ChartDemo do
  use ExRatatui.App

  @legend_positions [:top_right, :top_left, :bottom_right, :bottom_left, :top, :bottom, nil]
  @markers [:braille, :dot, :block]

  @cpu Enum.map(0..19, fn x -> {x / 1, 30.0 + 20.0 * :math.sin(x / 3)} end)
  @mem Enum.map(0..19, fn x -> {x / 1, 65.0 + 8.0 * :math.sin(x / 5 + 1)} end)

  @impl true
  def mount(_opts), do: {:ok, %{legend_index: 0, marker_index: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [chart_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}])

    legend_position = Enum.at(@legend_positions, state.legend_index)
    marker = Enum.at(@markers, state.marker_index)
    legend_label = if legend_position, do: Atom.to_string(legend_position), else: "hidden"

    chart = %Chart{
      datasets: [
        %Dataset{
          name: "CPU %",
          data: @cpu,
          marker: marker,
          graph_type: :line,
          style: %Style{fg: :cyan}
        },
        %Dataset{
          name: "Memory %",
          data: @mem,
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

    help = %Paragraph{
      text: "  l = legend position   m = marker   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{chart, chart_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: "l", kind: "press"}, state) do
    {:noreply, %{state | legend_index: rem(state.legend_index + 1, length(@legend_positions))}}
  end

  def handle_event(%Event.Key{code: "m", kind: "press"}, state) do
    {:noreply, %{state | marker_index: rem(state.marker_index + 1, length(@markers))}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = ChartDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
