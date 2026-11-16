# Example: a hand pointer over a clickable region (OSC 22 pointer shapes).
# Run with: EX_RATATUI_POINTER=1 mix run examples/basics/mouse_pointer.exs
#
# Controls: move the mouse over the button; q = quit
#
# Nothing detects whether a terminal understands pointer shapes (kitty and
# Ghostty do), so the app decides: here EX_RATATUI_POINTER=1 is that
# decision. Without it the app never returns `pointer:` and the arrow stays
# as it is. Hovering changes nothing on screen, so mouse moves return
# `render?: false`.

defmodule MousePointerDemo do
  use ExRatatui.App

  alias ExRatatui.Event.{Key, Mouse}
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  @impl true
  def mount(_opts), do: {:ok, System.get_env("EX_RATATUI_POINTER") == "1"}

  @impl true
  def render(supported?, _frame) do
    [
      {%Paragraph{text: "[ Hover here ]"}, %Rect{x: 2, y: 2, width: 14, height: 1}},
      {%Paragraph{text: hint(supported?)}, %Rect{x: 2, y: 4, width: 56, height: 1}}
    ]
  end

  @impl true
  def handle_event(%Mouse{kind: "moved", x: x, y: y}, true = supported?) do
    shape = if y == 2 and x in 2..15, do: :pointer, else: :default
    {:noreply, supported?, pointer: shape, render?: false}
  end

  def handle_event(%Key{code: "q"}, state), do: {:stop, state}
  def handle_event(_event, state), do: {:noreply, state, render?: false}

  defp hint(true), do: "Move outside to reset. Press q to exit."
  defp hint(false), do: "Pointer shapes are off (EX_RATATUI_POINTER=1). q exits."
end

# Start the app directly (not supervised, since this is a script)
{:ok, pid} = MousePointerDemo.start_link(name: nil, mouse_capture: true)

# Wait for the GenServer to exit
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
