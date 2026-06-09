# Example: Popup — overlay a centered widget on top of the rest of the UI.
# Run with: mix run examples/widgets/popup.exs
#
# Controls: Space = toggle popup, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, List, Paragraph, Popup}

defmodule PopupDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts), do: {:ok, %{show: true}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    background = %List{
      items: Enum.map(1..20, fn n -> "  Background row #{n}" end),
      style: %Style{fg: :dark_gray},
      block: %Block{
        title: " Background ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    widgets = [{background, area}]

    if state.show do
      popup = %Popup{
        content: %Paragraph{
          text:
            "\n  This is a Popup.\n\n  It floats over the background,\n  sized as a percentage of the area.\n\n  Press Space to dismiss it.",
          style: %Style{fg: :white}
        },
        block: %Block{
          title: " Notice ",
          borders: [:all],
          border_type: :rounded,
          border_style: %Style{fg: :cyan}
        },
        percent_width: 50,
        percent_height: 40
      }

      widgets ++ [{popup, area}]
    else
      hint = %Paragraph{
        text: " Space = show popup   q = quit",
        style: %Style{fg: :dark_gray}
      }

      widgets ++ [{hint, %Rect{x: 0, y: area.height - 1, width: area.width, height: 1}}]
    end
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: " ", kind: "press"}, state) do
    {:noreply, %{state | show: not state.show}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = PopupDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
