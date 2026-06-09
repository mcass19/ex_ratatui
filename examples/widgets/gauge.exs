# Example: Gauge — a block progress bar with a percentage label.
# Run with: mix run examples/widgets/gauge.exs
#
# Controls: Up/Down = adjust the top gauge, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Gauge, Paragraph}

defmodule GaugeDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts), do: {:ok, %{ratio: 0.45}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [adjustable_area, download_area, disk_area, help_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:length, 3}, {:length, 3}, {:min, 0}])

    [
      {gauge("Adjustable", state.ratio, :cyan), adjustable_area},
      {gauge("Download", 0.72, :green), download_area},
      {gauge("Disk", 0.91, :red), disk_area},
      {help(), help_area}
    ]
  end

  defp gauge(title, ratio, fg) do
    %Gauge{
      ratio: ratio,
      label: "#{round(ratio * 100)}%",
      gauge_style: %Style{fg: fg},
      block: %Block{
        title: " #{title} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp help do
    %Paragraph{
      text: "  Up/Down = adjust the top gauge   q = quit",
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

{:ok, pid} = GaugeDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
