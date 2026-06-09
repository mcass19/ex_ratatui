# Example: Clear — blank a region before drawing a manual overlay.
# Run with: mix run examples/widgets/clear.exs
#
# Controls: Space = toggle the Clear under the overlay, q = quit
#
# A bordered overlay is drawn over dense background text. With the Clear in
# place, the region behind the overlay is blanked; without it, the background
# bleeds through the gaps. (`Popup` does this clearing automatically — `Clear`
# is the primitive for hand-rolled overlays.)

alias ExRatatui.Event
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Clear, Paragraph}

defmodule ClearDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts), do: {:ok, %{clear: true}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    background = %Paragraph{
      text: String.duplicate("ratatui ", 2_000),
      style: %Style{fg: :dark_gray},
      wrap: true,
      block: %Block{title: " Background ", borders: [:all], border_style: %Style{fg: :dark_gray}}
    }

    overlay_area = centered(area, 40, 9)

    overlay = %Paragraph{
      text: "\n  Overlay (Clear: #{state.clear})\n\n  Space toggles the Clear behind me.",
      style: %Style{fg: :white},
      block: %Block{
        title: " Overlay ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    overlay_widgets =
      if state.clear do
        [{%Clear{}, overlay_area}, {overlay, overlay_area}]
      else
        [{overlay, overlay_area}]
      end

    help = %Paragraph{
      text: "  Space = toggle Clear   q = quit",
      style: %Style{fg: :dark_gray}
    }

    [{background, area}] ++
      overlay_widgets ++ [{help, %Rect{x: 0, y: area.height - 1, width: area.width, height: 1}}]
  end

  defp centered(%Rect{} = area, w, h) do
    width = min(w, area.width)
    height = min(h, area.height)

    %Rect{
      x: area.x + div(area.width - width, 2),
      y: area.y + div(area.height - height, 2),
      width: width,
      height: height
    }
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: " ", kind: "press"}, state),
    do: {:noreply, %{state | clear: not state.clear}}

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = ClearDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
