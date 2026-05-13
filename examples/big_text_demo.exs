# Example: interactive BigText viewer — cycle pixel size, alignment,
# color and title at runtime to see how each variant looks.
#
# Run with:
#   mix run examples/big_text_demo.exs
#
# Controls:
#   p — cycle pixel size  (full / half_height / half_width / quadrant /
#                          third_height / sextant / quarter_height / octant)
#   a — cycle alignment   (left / center / right)
#   c — cycle fg color    (magenta / cyan / yellow / green / red / white)
#   n — cycle title text  (cycles through a few sample slide headlines)
#   q — quit
#
# Visual reference for picking a pixel_size on a slide deck:
#   :full         — 8 rows tall, biggest impact. Great for a single word.
#   :half_height  — 4 rows tall, dense but readable. Fits a short title bar.
#   :quadrant     — 4 rows × half cols. Good middle ground.
#   :octant       — 1 row × half cols. Densest; closer to "bold caps".

alias ExRatatui.BigText
alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph}

defmodule BigTextDemo do
  use ExRatatui.App

  @pixel_sizes [
    :full,
    :half_height,
    :half_width,
    :quadrant,
    :third_height,
    :sextant,
    :quarter_height,
    :octant
  ]

  @alignments [:left, :center, :right]
  @colors [:magenta, :cyan, :yellow, :green, :red, :white]
  @titles ["EX_RATATUI", "SLIDES", "TUI ROCKS", "HELLO"]

  @impl true
  def mount(_opts) do
    {:ok,
     %{
       title: hd(@titles),
       pixel_size: :quadrant,
       alignment: :center,
       color: :magenta
     }}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [banner_area, status_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 4}, {:length, 3}])

    banner =
      BigText.new(state.title,
        pixel_size: state.pixel_size,
        alignment: state.alignment,
        style: %Style{fg: state.color, modifiers: [:bold]},
        block: %Block{
          title: " #{inspect(state.pixel_size)} · #{inspect(state.alignment)} ",
          borders: [:all],
          border_type: :rounded,
          border_style: %Style{fg: :dark_gray}
        }
      )

    status = %Paragraph{
      text: status_text(state),
      style: %Style{fg: :light_cyan, modifiers: [:bold]},
      block: %Block{borders: [:all], border_type: :rounded, title: " status "}
    }

    help = %Paragraph{
      text: "  p = pixel_size   a = alignment   c = color   n = next title   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [
      {banner, banner_area},
      {status, status_area},
      {help, help_area}
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "p", kind: "press"}, state) do
    {:noreply, %{state | pixel_size: cycle(@pixel_sizes, state.pixel_size)}}
  end

  def handle_event(%Event.Key{code: "a", kind: "press"}, state) do
    {:noreply, %{state | alignment: cycle(@alignments, state.alignment)}}
  end

  def handle_event(%Event.Key{code: "c", kind: "press"}, state) do
    {:noreply, %{state | color: cycle(@colors, state.color)}}
  end

  def handle_event(%Event.Key{code: "n", kind: "press"}, state) do
    {:noreply, %{state | title: cycle(@titles, state.title)}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp cycle(options, current) do
    idx = Enum.find_index(options, &(&1 == current)) || 0
    Enum.at(options, rem(idx + 1, length(options)))
  end

  defp status_text(state) do
    """
      title: #{inspect(state.title)}
      pixel_size: #{inspect(state.pixel_size)}   alignment: #{inspect(state.alignment)}   color: #{inspect(state.color)}\
    """
  end
end

{:ok, pid} = BigTextDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
