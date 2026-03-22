# Example: Tabs widget demo.
# Run with: EX_RATATUI_BUILD=true mix run examples/tabs_demo.exs
#
# Controls: Left/Right = switch tabs, q = quit

alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph, Tabs}
alias ExRatatui.Event

defmodule TabsDemo do
  use ExRatatui.App

  @tabs ["Home", "Settings", "Profile", "Help"]

  @impl true
  def mount(_opts) do
    {:ok, %{selected: 0}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [tabs_area, body_area, footer_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 1}])

    tabs = %Tabs{
      titles: @tabs,
      selected: state.selected,
      style: %Style{fg: :dark_gray},
      highlight_style: %Style{fg: :cyan, modifiers: [:bold]},
      divider: " | ",
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    body = %Paragraph{
      text: "\n  You are viewing: #{Enum.at(@tabs, state.selected)}",
      style: %Style{fg: :white},
      block: %Block{
        title: " #{Enum.at(@tabs, state.selected)} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    footer = %Paragraph{
      text: " Left/Right = switch tabs  |  q = quit",
      style: %Style{fg: :dark_gray}
    }

    [{tabs, tabs_area}, {body, body_area}, {footer, footer_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "right", kind: "press"}, state) do
    {:noreply, %{state | selected: rem(state.selected + 1, length(@tabs))}}
  end

  def handle_event(%Event.Key{code: "left", kind: "press"}, state) do
    {:noreply, %{state | selected: rem(state.selected - 1 + length(@tabs), length(@tabs))}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end

{:ok, pid} = TabsDemo.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
