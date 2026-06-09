# Example: Sparkline — a compact bar trend, including missing (nil) samples.
# Run with: mix run examples/widgets/sparkline.exs
#
# Controls: Space = shift in a new random sample, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph, Sparkline}

defmodule SparklineDemo do
  use ExRatatui.App

  # nil entries render as the absent_value_symbol — sparklines tolerate gaps.
  @seed [
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
  ]

  @impl true
  def mount(_opts), do: {:ok, %{data: @seed}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [chart_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}])

    sparkline = %Sparkline{
      data: state.data,
      max: 25,
      bar_set: :nine_levels,
      style: %Style{fg: :green},
      absent_value_symbol: "·",
      absent_value_style: %Style{fg: :dark_gray},
      block: %Block{
        title: " CPU Load (last #{length(state.data)} samples · nil = missing) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    help = %Paragraph{
      text: "  Space = shift in a new sample   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{sparkline, chart_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: " ", kind: "press"}, state) do
    next = Enum.at(state.data, -1) || 10
    sample = max(0, min(25, next + Enum.random(-4..4)))
    {:noreply, %{state | data: tl(state.data) ++ [sample]}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = SparklineDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
