# Example: State machine — screen-as-data dispatch with a modal overlay.
# Run with: mix run examples/observability/state_machine.exs
#
# Controls:
#   main:     s = open settings, q = ask to quit
#   settings: Up/Down = move, Space = toggle, Esc = back to main
#   quit modal: y = quit, n / Esc = cancel
#
# Follows guides/state_machines.md: a `:screen` atom names the active state and
# `render/2` + `handle_event/2` dispatch on it, while an `:overlay` field models
# a modal layer that intercepts input before the underlying screen sees it.

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Checkbox, Paragraph, Popup}

defmodule StateMachineDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts) do
    {:ok,
     %{
       screen: :main,
       overlay: nil,
       cursor: 0,
       settings: [
         %{label: "Dark mode", checked: true},
         %{label: "Telemetry", checked: false},
         %{label: "Auto-save", checked: true}
       ]
     }}
  end

  # --- render: dispatch on screen, draw the overlay last -------------------

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    base = render_screen(state.screen, state, area)

    case state.overlay do
      nil -> base
      :confirm_quit -> base ++ [confirm_quit_popup(area)]
    end
  end

  defp render_screen(:main, _state, area) do
    body = %Paragraph{
      text: "\n  Main screen.\n\n  s = settings\n  q = quit",
      style: %Style{fg: :white},
      block: block(" Main ", :cyan)
    }

    [{body, area}]
  end

  defp render_screen(:settings, state, area) do
    items =
      state.settings
      |> Enum.with_index()
      |> Enum.map(fn {setting, idx} ->
        prefix = if idx == state.cursor, do: "> ", else: "  "

        %Checkbox{
          label: "#{prefix}#{setting.label}",
          checked: setting.checked,
          style: %Style{fg: :white},
          checked_style: %Style{fg: :green, modifiers: [:bold]}
        }
      end)

    [header_area | rows] =
      Layout.split(
        area,
        :vertical,
        [{:length, 2} | Enum.map(items, fn _ -> {:length, 1} end)] ++ [{:min, 0}]
      )

    header = %Paragraph{
      text: "  Settings (Esc = back)",
      style: %Style{fg: :cyan, modifiers: [:bold]},
      block: block(" Settings ", :cyan)
    }

    rows = Enum.drop(rows, -1)

    [{header, header_area} | Enum.zip(items, rows)]
  end

  defp confirm_quit_popup(area) do
    popup = %Popup{
      content: %Paragraph{
        text: "\n  Quit the demo?\n\n  y = yes    n / Esc = no",
        style: %Style{fg: :white},
        alignment: :center
      },
      block: block(" Confirm ", :red),
      percent_width: 40,
      percent_height: 30
    }

    {popup, area}
  end

  defp block(title, fg) do
    %Block{title: title, borders: [:all], border_type: :rounded, border_style: %Style{fg: fg}}
  end

  # --- events: overlay intercepts first, then dispatch on screen -----------

  @impl true
  def handle_event(event, %{overlay: :confirm_quit} = state), do: handle_overlay(event, state)
  def handle_event(event, %{screen: :main} = state), do: handle_main(event, state)
  def handle_event(event, %{screen: :settings} = state), do: handle_settings(event, state)
  def handle_event(_event, state), do: {:noreply, state}

  defp handle_overlay(%Event.Key{code: "y", kind: "press"}, state), do: {:stop, state}

  defp handle_overlay(%Event.Key{code: code, kind: "press"}, state) when code in ["n", "escape"],
    do: {:noreply, %{state | overlay: nil}}

  defp handle_overlay(_event, state), do: {:noreply, state}

  defp handle_main(%Event.Key{code: "s", kind: "press"}, state),
    do: {:noreply, %{state | screen: :settings, cursor: 0}}

  defp handle_main(%Event.Key{code: "q", kind: "press"}, state),
    do: {:noreply, %{state | overlay: :confirm_quit}}

  defp handle_main(_event, state), do: {:noreply, state}

  defp handle_settings(%Event.Key{code: "escape", kind: "press"}, state),
    do: {:noreply, %{state | screen: :main}}

  defp handle_settings(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"],
    do: {:noreply, %{state | cursor: rem(state.cursor + 1, length(state.settings))}}

  defp handle_settings(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"],
    do:
      {:noreply,
       %{state | cursor: rem(state.cursor - 1 + length(state.settings), length(state.settings))}}

  defp handle_settings(%Event.Key{code: " ", kind: "press"}, state) do
    settings =
      List.update_at(state.settings, state.cursor, fn s -> %{s | checked: not s.checked} end)

    {:noreply, %{state | settings: settings}}
  end

  defp handle_settings(_event, state), do: {:noreply, state}
end

{:ok, pid} = StateMachineDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
