# Example: WidgetList — a scrollable list of heterogeneous, multi-line widgets.
# Run with: mix run examples/widgets/widget_list.exs
#
# Controls: Up/Down = scroll, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Markdown, Paragraph, WidgetList}

defmodule WidgetListDemo do
  use ExRatatui.App

  # A chat-style transcript: each turn is a role label + content, with a spacer.
  @messages [
    {:user, "How do I render a table?"},
    {:ai, "Use the **Table** widget:\n\n```elixir\n%Table{rows: rows, header: header}\n```"},
    {:user, "And a list of mixed widgets?"},
    {:ai,
     "That's what `WidgetList` is for — each item is a `{widget, height}` tuple, so paragraphs, markdown, and gauges can share one scrollable column."},
    {:user, "Got it, thanks!"},
    {:ai, "Anytime. Scroll with Up/Down to revisit earlier turns."}
  ]

  @impl true
  def mount(_opts), do: {:ok, %{scroll: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [list_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}])

    items =
      Enum.flat_map(@messages, fn
        {:user, text} ->
          label = %Paragraph{
            text: " You ",
            style: %Style{fg: :black, bg: :green, modifiers: [:bold]}
          }

          content = %Paragraph{text: text, style: %Style{fg: :white}, wrap: true}
          [{label, 1}, {content, 1}, {spacer(), 1}]

        {:ai, text} ->
          label = %Paragraph{
            text: " AI ",
            style: %Style{fg: :black, bg: :magenta, modifiers: [:bold]}
          }

          content = %Markdown{content: text, wrap: true}
          lines = text |> String.split("\n") |> length()
          [{label, 1}, {content, max(1, lines)}, {spacer(), 1}]
      end)

    widget_list = %WidgetList{
      items: items,
      scroll_offset: state.scroll,
      block: %Block{
        title: " Transcript (#{length(@messages)} messages) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    help = %Paragraph{
      text: "  Up/Down = scroll   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{widget_list, list_area}, {help, help_area}]
  end

  defp spacer, do: %Paragraph{text: "", style: %Style{}}

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"] do
    {:noreply, %{state | scroll: state.scroll + 1}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"] do
    {:noreply, %{state | scroll: max(0, state.scroll - 1)}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = WidgetListDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
