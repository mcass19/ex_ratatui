# Example: List — a selectable list with a highlight symbol.
# Run with: mix run examples/widgets/list.exs
#
# Controls: Up/Down = move selection, g/G = jump to top/bottom, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, List, Paragraph}

defmodule ListDemo do
  use ExRatatui.App

  @fruits ~w(Apple Apricot Banana Blueberry Cherry Date Elderberry Fig Grape
             Kiwi Lemon Mango Nectarine Orange Papaya Quince Raspberry)

  @impl true
  def mount(_opts), do: {:ok, %{selected: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [list_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}])

    list = %List{
      items: @fruits,
      selected: state.selected,
      style: %Style{fg: :white},
      highlight_style: %Style{fg: :black, bg: :green, modifiers: [:bold]},
      highlight_symbol: "> ",
      block: %Block{
        title: " Fruit (#{state.selected + 1}/#{length(@fruits)}) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    help = %Paragraph{
      text: "  Up/Down = move   g/G = top/bottom   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{list, list_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"] do
    {:noreply, %{state | selected: min(length(@fruits) - 1, state.selected + 1)}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"] do
    {:noreply, %{state | selected: max(0, state.selected - 1)}}
  end

  def handle_event(%Event.Key{code: "g", kind: "press"}, state),
    do: {:noreply, %{state | selected: 0}}

  def handle_event(%Event.Key{code: "G", kind: "press"}, state),
    do: {:noreply, %{state | selected: length(@fruits) - 1}}

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = ListDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
