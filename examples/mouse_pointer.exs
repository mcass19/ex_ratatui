# Run in a terminal supporting OSC 22 CSS pointer shapes:
# EX_RATATUI_POINTER=1 mix run examples/mouse_pointer.exs
# Omit EX_RATATUI_POINTER to exercise the inert fallback on unknown terminals.

defmodule MousePointerDemo do
  use ExRatatui.App

  alias ExRatatui.Event.{Key, Mouse}
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  @impl true
  def mount(_opts), do: {:ok, System.get_env("EX_RATATUI_POINTER") == "1"}

  @impl true
  def render(_supported?, _frame) do
    [
      {%Paragraph{text: "[ Hover here ]"}, %Rect{x: 2, y: 2, width: 14, height: 1}},
      {%Paragraph{text: "Move outside to reset. Press q to exit."},
       %Rect{x: 2, y: 4, width: 45, height: 1}}
    ]
  end

  @impl true
  def handle_event(%Mouse{kind: "moved", x: x, y: y}, true = supported?) do
    shape = if y == 2 and x in 2..15, do: :pointer, else: :default
    {:noreply, supported?, pointer: shape, render?: false}
  end

  def handle_event(%Key{code: "q"}, state), do: {:stop, state}
  def handle_event(_event, state), do: {:noreply, state, render?: false}
end

{:ok, pid} = MousePointerDemo.start_link(name: nil, mouse_capture: true)
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
