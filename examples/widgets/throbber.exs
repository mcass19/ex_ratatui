# Example: Throbber — animated spinners, one per throbber_set.
# Run with: mix run examples/widgets/throbber.exs
#
# Controls: q = quit
#
# Uses the reducer runtime: a Subscription.interval drives the animation,
# which is a better fit for time-based ticks than Process.send_after.

defmodule ThrobberDemo do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.Widgets.{Block, Paragraph, Throbber}

  @sets [:braille, :dots, :ascii, :arrow, :clock, :box_drawing, :quadrant_block, :white_circle]

  @impl true
  def init(_opts), do: {:ok, %{step: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    rows = Enum.map(@sets, fn _ -> {:length, 1} end)

    [header_area | rest] =
      Layout.split(area, :vertical, [{:length, 2} | rows] ++ [{:min, 0}])

    {set_areas, [help_area]} = Enum.split(rest, length(@sets))

    header = %Paragraph{
      text: "  Throbber sets (step #{state.step})",
      style: %Style{fg: :cyan, modifiers: [:bold]}
    }

    throbbers =
      @sets
      |> Enum.zip(set_areas)
      |> Enum.map(fn {set, set_area} ->
        throbber = %Throbber{
          label: "  #{set}",
          step: state.step,
          throbber_set: set,
          style: %Style{fg: :white},
          throbber_style: %Style{fg: :cyan, modifiers: [:bold]}
        }

        {throbber, set_area}
      end)

    help = %Paragraph{
      text: "  q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{header, header_area} | throbbers] ++ [{help, help_area}]
  end

  @impl true
  def update({:event, %Event.Key{code: "q", kind: "press"}}, state), do: {:stop, state}

  def update({:info, :tick}, state), do: {:noreply, %{state | step: state.step + 1}}

  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state) do
    [Subscription.interval(:throbber_tick, 120, :tick)]
  end
end

{:ok, pid} = ThrobberDemo.start_link(name: nil)

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
