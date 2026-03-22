# Example: LineGauge widget demo.
# Run with: EX_RATATUI_BUILD=true mix run examples/line_gauge_demo.exs
#
# Controls: Right = increase, Left = decrease, q = quit

alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, LineGauge, Paragraph}
alias ExRatatui.Event

defmodule LineGaugeDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts) do
    {:ok, %{download: 0.0, upload: 0.0, sync: 0.0}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, g1_area, g2_area, g3_area, _spacer, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 3},
        {:length, 3},
        {:length, 3},
        {:min, 0},
        {:length, 1}
      ])

    header = %Paragraph{
      text: "  LineGauge Demo",
      style: %Style{fg: :cyan, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    download = %LineGauge{
      ratio: state.download,
      label: "Download: #{round(state.download * 100)}%",
      filled_style: %Style{fg: :green},
      unfilled_style: %Style{fg: :dark_gray},
      block: %Block{borders: [:all], border_type: :rounded, border_style: %Style{fg: :dark_gray}}
    }

    upload = %LineGauge{
      ratio: state.upload,
      label: "Upload: #{round(state.upload * 100)}%",
      filled_style: %Style{fg: :blue},
      unfilled_style: %Style{fg: :dark_gray},
      block: %Block{borders: [:all], border_type: :rounded, border_style: %Style{fg: :dark_gray}}
    }

    sync = %LineGauge{
      ratio: state.sync,
      label: "Sync: #{round(state.sync * 100)}%",
      filled_style: %Style{fg: :magenta},
      unfilled_style: %Style{fg: :dark_gray},
      block: %Block{borders: [:all], border_type: :rounded, border_style: %Style{fg: :dark_gray}}
    }

    footer = %Paragraph{
      text: " Right = +5%  |  Left = -5%  |  q = quit",
      style: %Style{fg: :dark_gray}
    }

    [
      {header, header_area},
      {download, g1_area},
      {upload, g2_area},
      {sync, g3_area},
      {footer, footer_area}
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "right", kind: "press"}, state) do
    {:noreply,
     %{
       state
       | download: min(state.download + 0.05, 1.0),
         upload: min(state.upload + 0.03, 1.0),
         sync: min(state.sync + 0.07, 1.0)
     }}
  end

  def handle_event(%Event.Key{code: "left", kind: "press"}, state) do
    {:noreply,
     %{
       state
       | download: max(state.download - 0.05, 0.0),
         upload: max(state.upload - 0.03, 0.0),
         sync: max(state.sync - 0.07, 0.0)
     }}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end

{:ok, pid} = LineGaugeDemo.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
