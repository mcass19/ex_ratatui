defmodule ReducerCounterApp do
  @moduledoc """
  Example: supervised counter using the reducer runtime.
  Run with: mix run examples/reducer_counter_app.exs

  Controls: Up/k = increment, Down/j = decrement, q = quit

  This is the same counter as counter_app.exs but structured with the
  reducer runtime (init/1, update/2, subscriptions/1) instead of callbacks.
  """

  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts) do
    {:ok, %{count: 0}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, body_area, footer_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 3}])

    header = %Paragraph{
      text: "  ExRatatui Counter (Reducer)",
      style: %Style{fg: :cyan, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    body = %Paragraph{
      text: "\n\n  Counter: #{state.count}",
      style: %Style{fg: :white, modifiers: [:bold]},
      alignment: :center,
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    footer = %Paragraph{
      text: " Up/k = +1  |  Down/j = -1  |  q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{
        borders: [:top],
        border_style: %Style{fg: :dark_gray}
      }
    }

    [{header, header_area}, {body, body_area}, {footer, footer_area}]
  end

  @impl true
  def update({:event, %Event.Key{code: "q", kind: "press"}}, state), do: {:stop, state}

  def update({:event, %Event.Key{code: code, kind: "press"}}, state)
      when code in ["up", "k"] do
    {:noreply, %{state | count: state.count + 1}}
  end

  def update({:event, %Event.Key{code: code, kind: "press"}}, state)
      when code in ["down", "j"] do
    {:noreply, %{state | count: state.count - 1}}
  end

  def update({:info, :tick}, state) do
    {:noreply, %{state | count: state.count + 1}}
  end

  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state) do
    [Subscription.interval(:counter_tick, 1_000, :tick)]
  end
end

{:ok, pid} = ReducerCounterApp.start_link(name: nil)

# Wait for the GenServer to exit
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
