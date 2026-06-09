# Example: LineGauge — a single-line progress bar, denser than Gauge.
# Run with: mix run examples/widgets/line_gauge.exs
#
# Controls: Up/Down = adjust the top gauge, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, LineGauge, Paragraph}

defmodule LineGaugeDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts), do: {:ok, %{ratio: 0.45}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [box_area, help_area] =
      Layout.split(area, :vertical, [{:length, 6}, {:min, 0}])

    [cpu_area, mem_area, net_area] =
      Layout.split(inner(box_area), :vertical, [{:length, 1}, {:length, 1}, {:length, 1}])

    box = %Paragraph{
      text: "",
      block: %Block{
        title: " Live metrics ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    [
      {box, box_area},
      {line_gauge("CPU ", state.ratio, :cyan), cpu_area},
      {line_gauge("MEM ", 0.62, :green), mem_area},
      {line_gauge("NET ", 0.18, :magenta), net_area},
      {help(), help_area}
    ]
  end

  defp line_gauge(label, ratio, fg) do
    %LineGauge{
      ratio: ratio,
      label: "#{label} #{round(ratio * 100)}%",
      filled_style: %Style{fg: fg},
      unfilled_style: %Style{fg: :dark_gray}
    }
  end

  defp inner(%Rect{x: x, y: y, width: w, height: h}) do
    %Rect{x: x + 2, y: y + 1, width: max(w - 4, 0), height: max(h - 2, 0)}
  end

  defp help do
    %Paragraph{
      text: "  Up/Down = adjust CPU   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"] do
    {:noreply, %{state | ratio: min(1.0, state.ratio + 0.05)}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"] do
    {:noreply, %{state | ratio: max(0.0, state.ratio - 0.05)}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = LineGaugeDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
