# Example: Telemetry — a TUI that observes its own runtime events live.
# Run with: mix run examples/observability/telemetry.exs
#
# Controls: any key bumps the event counters, q = quit
#
# Attaches a :telemetry handler to ExRatatui's runtime/render span :stop
# events and tallies them into an Agent, then renders the running counts.
# Every keypress drives a handle_event + render, so the counts climb with each
# interaction. See guides/internals/telemetry.md for the full event catalog.

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, List, Paragraph}

defmodule TelemetryDemo do
  use ExRatatui.App

  @events [
    [:ex_ratatui, :runtime, :init, :stop],
    [:ex_ratatui, :runtime, :event, :stop],
    [:ex_ratatui, :render, :frame, :stop]
  ]

  @impl true
  def mount(_opts) do
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    handler_id = {__MODULE__, self()}

    :telemetry.attach_many(handler_id, @events, &__MODULE__.handle_telemetry/4, agent)

    {:ok, %{agent: agent, handler_id: handler_id}}
  end

  # Runs in the process that emits the event; tallies into the Agent.
  def handle_telemetry(event, _measurements, _metadata, agent) do
    Agent.update(agent, fn counts -> Map.update(counts, event, 1, &(&1 + 1)) end)
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, list_area, help_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 3}])

    counts = Agent.get(state.agent, & &1)

    items =
      Enum.map(@events, fn event ->
        name = event |> Enum.map(&to_string/1) |> Enum.join(".")
        "  #{String.pad_trailing(name, 32)} #{Map.get(counts, event, 0)}"
      end)

    header = %Paragraph{
      text: "  ExRatatui telemetry — live event counts",
      style: %Style{fg: :cyan, modifiers: [:bold]}
    }

    list = %List{
      items: items,
      style: %Style{fg: :white},
      block: %Block{
        title: " :stop events ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    help = %Paragraph{
      text: "  Press any key to bump the counters   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{header, header_area}, {list, list_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}
  def handle_event(_event, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end
end

{:ok, pid} = TelemetryDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
