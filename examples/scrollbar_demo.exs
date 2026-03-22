# Example: Scrollbar widget demo.
# Run with: EX_RATATUI_BUILD=true mix run examples/scrollbar_demo.exs
#
# Controls: Up/Down = scroll, q = quit

alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph, Scrollbar}
alias ExRatatui.Event

defmodule ScrollbarDemo do
  use ExRatatui.App

  @lines 50

  @impl true
  def mount(_opts) do
    {:ok, %{scroll: 0}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [body_area, footer_area] = Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])

    # Content area (leave 1 col on right for scrollbar)
    content_width = body_area.width - 1
    content_area = %Rect{body_area | width: content_width}
    scrollbar_area = %Rect{body_area | x: content_width, width: 1}

    visible_lines = body_area.height - 2
    text = Enum.map_join(0..(@lines - 1), "\n", fn i -> "  Line #{i + 1}: Sample content" end)

    content = %Paragraph{
      text: text,
      style: %Style{fg: :white},
      scroll: {state.scroll, 0},
      block: %Block{
        title: " Scrollable Content (#{state.scroll + 1}/#{@lines}) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    scrollbar = %Scrollbar{
      content_length: @lines,
      position: state.scroll,
      viewport_content_length: visible_lines,
      thumb_style: %Style{fg: :cyan},
      track_style: %Style{fg: :dark_gray}
    }

    footer = %Paragraph{
      text: " Up/Down = scroll  |  q = quit",
      style: %Style{fg: :dark_gray}
    }

    [{content, content_area}, {scrollbar, scrollbar_area}, {footer, footer_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, state) do
    {:noreply, %{state | scroll: min(state.scroll + 1, @lines - 1)}}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, state) do
    {:noreply, %{state | scroll: max(state.scroll - 1, 0)}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end

{:ok, pid} = ScrollbarDemo.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
