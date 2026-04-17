defmodule ExRatatui.Test.PeerRichApp do
  @moduledoc false
  # Rich-text variant of PeerApp, used by the distributed integration test to
  # prove that ExRatatui.Text.{Span, Line} structs survive the node boundary
  # intact when rendered on a remote node and shipped to the local client.

  use ExRatatui.App

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.Paragraph

  @impl true
  def mount(opts) do
    test_pid = Keyword.fetch!(opts, :test_pid)
    send(test_pid, {:mounted, self(), opts})
    {:ok, %{test_pid: test_pid}}
  end

  @impl true
  def render(_state, frame) do
    widget = %Paragraph{
      text:
        Line.new([
          Span.new("status: ", style: %Style{fg: :white}),
          Span.new("OK", style: %Style{fg: :green, modifiers: [:bold]})
        ])
    }

    rect = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [{widget, rect}]
  end

  @impl true
  def handle_event(%ExRatatui.Event.Key{code: "q"}, state) do
    {:stop, state}
  end

  def handle_event(_event, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    send(state.test_pid, {:terminated, reason})
    :ok
  end
end
