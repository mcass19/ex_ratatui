# Example: Scrollbar — a position indicator bound to a scrollable List.
# Run with: mix run examples/widgets/scrollbar.exs
#
# Controls: Up/Down = move selection (scrollbar tracks it), q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, List, Scrollbar}

defmodule ScrollbarDemo do
  use ExRatatui.App

  @items Enum.map(1..50, fn n -> "  Item #{n}" end)

  @impl true
  def mount(_opts), do: {:ok, %{selected: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    # Reserve the last column for the scrollbar.
    list_area = %Rect{area | width: area.width - 1}
    scrollbar_area = %Rect{area | x: area.x + area.width - 1, width: 1}

    list = %List{
      items: @items,
      selected: state.selected,
      highlight_style: %Style{fg: :black, bg: :cyan, modifiers: [:bold]},
      highlight_symbol: "> ",
      block: %Block{
        title: " #{length(@items)} items (#{state.selected + 1} selected) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    scrollbar = %Scrollbar{
      orientation: :vertical_right,
      content_length: length(@items),
      position: state.selected,
      thumb_style: %Style{fg: :cyan},
      track_style: %Style{fg: :dark_gray}
    }

    [{list, list_area}, {scrollbar, scrollbar_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"] do
    {:noreply, %{state | selected: min(length(@items) - 1, state.selected + 1)}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"] do
    {:noreply, %{state | selected: max(0, state.selected - 1)}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = ScrollbarDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
