# Example: Tabs — a tab bar selecting between content panes.
# Run with: mix run examples/widgets/tabs.exs
#
# Controls: Left/Right (or Tab) = switch tab, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph, Tabs}

defmodule TabsDemo do
  use ExRatatui.App

  @titles ["Overview", "Metrics", "Logs", "About"]

  @bodies %{
    0 => "Overview — a summary of the system.",
    1 => "Metrics — charts and counters live here.",
    2 => "Logs — recent events scroll through here.",
    3 => "About — version, authors, and links."
  }

  @impl true
  def mount(_opts), do: {:ok, %{selected: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [tabs_area, body_area, help_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 3}])

    tabs = %Tabs{
      titles: @titles,
      selected: state.selected,
      style: %Style{fg: :white},
      highlight_style: %Style{fg: :black, bg: :cyan, modifiers: [:bold]},
      divider: "|",
      block: %Block{borders: [:all], border_type: :rounded, border_style: %Style{fg: :dark_gray}}
    }

    body = %Paragraph{
      text: "\n  " <> Map.fetch!(@bodies, state.selected),
      style: %Style{fg: :white},
      block: %Block{
        title: " #{Enum.at(@titles, state.selected)} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    help = %Paragraph{
      text: "  Left/Right or Tab = switch   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{tabs, tabs_area}, {body, body_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state)
      when code in ["right", "tab", "l"] do
    {:noreply, %{state | selected: rem(state.selected + 1, length(@titles))}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["left", "h"] do
    {:noreply, %{state | selected: rem(state.selected - 1 + length(@titles), length(@titles))}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = TabsDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
