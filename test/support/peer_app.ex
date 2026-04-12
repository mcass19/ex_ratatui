defmodule ExRatatui.Test.PeerApp do
  @moduledoc false
  # A test App module compiled to disk (via elixirc_paths) so it can be
  # loaded on :peer nodes for distributed integration tests.

  use ExRatatui.App

  @impl true
  def mount(opts) do
    test_pid = Keyword.fetch!(opts, :test_pid)
    send(test_pid, {:mounted, self(), opts})
    {:ok, %{test_pid: test_pid, count: 0}}
  end

  @impl true
  def render(state, frame) do
    alias ExRatatui.Widgets.Paragraph
    alias ExRatatui.Layout.Rect

    widget = %Paragraph{text: "count: #{state.count}"}
    rect = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [{widget, rect}]
  end

  @impl true
  def handle_event(%ExRatatui.Event.Key{code: "q"}, state) do
    {:stop, state}
  end

  def handle_event(_event, state) do
    {:noreply, %{state | count: state.count + 1}}
  end

  @impl true
  def handle_info({:custom_msg, val}, state) do
    send(state.test_pid, {:got_custom, val})
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    send(state.test_pid, {:terminated, reason})
    :ok
  end
end
