defmodule ReducerCounterApp do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout.Rect, Subscription}
  alias ExRatatui.Widgets.Paragraph

  @impl true
  def init(_opts) do
    {:ok, %{count: 0}}
  end

  @impl true
  def render(state, frame) do
    text = """
    Reducer counter

    Count: #{state.count}

    Up: increment
    Down: decrement
    q: quit
    """

    [{%Paragraph{text: text}, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  @impl true
  def update({:event, %Event.Key{code: "q"}}, state), do: {:stop, state}

  def update({:event, %Event.Key{code: "up"}}, state) do
    {:noreply, %{state | count: state.count + 1}}
  end

  def update({:event, %Event.Key{code: "down"}}, state) do
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

{:ok, _pid} = ReducerCounterApp.start_link(name: nil)
Process.sleep(:infinity)
