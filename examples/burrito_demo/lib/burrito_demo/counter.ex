defmodule BurritoDemo.Counter do
  @moduledoc """
  Counter TUI ported from `examples/counter_app.exs`. Same widget tree,
  same key bindings — just packaged as a real module instead of a script.
  """

  use ExRatatui.App

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  @impl true
  def mount(_opts), do: {:ok, %{count: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, body_area, footer_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 3}])

    header = %Paragraph{
      text: "  burrito_demo Counter",
      style: %Style{fg: :cyan, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    body = %Paragraph{
      text: "\n\n  Counter: #{state.count}",
      style: %Style{fg: :white, modifiers: [:bold]},
      alignment: :center,
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    footer = %Paragraph{
      text: " Up/k = +1   Down/j = -1   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{
        borders: [:top],
        border_style: %Style{fg: :dark_gray}
      }
    }

    [{header, header_area}, {body, body_area}, {footer, footer_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"] do
    {:noreply, %{state | count: state.count + 1}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"] do
    {:noreply, %{state | count: state.count - 1}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end
