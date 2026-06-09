# Example: Canvas — draw shapes in a bounded coordinate space, plus a world map.
# Run with: mix run examples/widgets/canvas.exs
#
# Controls: Arrow keys = move the cursor point, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Canvas, Paragraph}
alias ExRatatui.Widgets.Canvas.{Circle, Label, Line, Points, Rectangle}
alias ExRatatui.Widgets.Canvas.Map, as: CanvasMap

defmodule CanvasDemo do
  use ExRatatui.App

  @x_bounds {0.0, 100.0}
  @y_bounds {0.0, 50.0}

  @shapes [
    %Line{x1: 0.0, y1: 0.0, x2: 100.0, y2: 0.0, color: :dark_gray},
    %Line{x1: 0.0, y1: 0.0, x2: 0.0, y2: 50.0, color: :dark_gray},
    %Circle{x: 30.0, y: 30.0, radius: 8.0, color: :cyan},
    %Rectangle{x: 55.0, y: 10.0, width: 25.0, height: 15.0, color: :yellow},
    %Points{coords: [{70.0, 35.0}, {75.0, 38.0}, {80.0, 42.0}, {85.0, 40.0}], color: :magenta}
  ]

  @impl true
  def mount(_opts), do: {:ok, %{cursor: {50.0, 25.0}}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [plot_area, map_area, help_area] =
      Layout.split(area, :vertical, [{:percentage, 55}, {:min, 0}, {:length, 1}])

    cursor_point = %Points{coords: [state.cursor], color: :white}

    plot = %Canvas{
      x_bounds: @x_bounds,
      y_bounds: @y_bounds,
      marker: :braille,
      shapes: @shapes ++ [cursor_point],
      block: %Block{
        title: " Plot (Line, Circle, Rectangle, Points) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    world_map = %Canvas{
      x_bounds: {-180.0, 180.0},
      y_bounds: {-90.0, 90.0},
      marker: :dot,
      shapes: [
        %CanvasMap{resolution: :high, color: :green},
        %Label{x: -74.0, y: 40.7, text: "NYC", color: :yellow},
        %Label{x: -0.1, y: 51.5, text: "London", color: :yellow},
        %Label{x: 139.7, y: 35.7, text: "Tokyo", color: :yellow},
        %Label{x: -46.6, y: -23.5, text: "São Paulo", color: :yellow}
      ],
      block: %Block{
        title: " World Map (CanvasMap + Label) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :green}
      }
    }

    {cx, cy} = state.cursor

    help = %Paragraph{
      text:
        "  Cursor: (#{:erlang.float_to_binary(cx, decimals: 1)}, " <>
          "#{:erlang.float_to_binary(cy, decimals: 1)})   Arrow keys = move   q = quit",
      style: %Style{fg: :dark_gray}
    }

    [{plot, plot_area}, {world_map, map_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: "Right", kind: "press"}, state),
    do: {:noreply, move(state, 5.0, 0.0)}

  def handle_event(%Event.Key{code: "Left", kind: "press"}, state),
    do: {:noreply, move(state, -5.0, 0.0)}

  def handle_event(%Event.Key{code: "Up", kind: "press"}, state),
    do: {:noreply, move(state, 0.0, 5.0)}

  def handle_event(%Event.Key{code: "Down", kind: "press"}, state),
    do: {:noreply, move(state, 0.0, -5.0)}

  def handle_event(_event, state), do: {:noreply, state}

  defp move(state, dx, dy) do
    {cx, cy} = state.cursor
    {min_x, max_x} = @x_bounds
    {min_y, max_y} = @y_bounds
    cursor = {clamp(cx + dx, min_x, max_x), clamp(cy + dy, min_y, max_y)}
    %{state | cursor: cursor}
  end

  defp clamp(value, min, max), do: value |> max(min) |> min(max)
end

{:ok, pid} = CanvasDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
