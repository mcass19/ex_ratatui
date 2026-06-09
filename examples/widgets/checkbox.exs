# Example: Checkbox — a toggleable settings list with a moving cursor.
# Run with: mix run examples/widgets/checkbox.exs
#
# Controls: Up/Down = move cursor, Space = toggle, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Checkbox, Paragraph}

defmodule CheckboxDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts) do
    {:ok,
     %{
       cursor: 0,
       settings: [
         %{label: "Enable notifications", checked: true},
         %{label: "Dark mode", checked: false},
         %{label: "Auto-update", checked: true},
         %{label: "Show line numbers", checked: false},
         %{label: "Vim keybindings", checked: false}
       ]
     }}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    rows = Enum.map(state.settings, fn _ -> {:length, 1} end)
    areas = Layout.split(area, :vertical, [{:length, 2} | rows] ++ [{:min, 0}])

    header = %Paragraph{
      text: "  Preferences",
      style: %Style{fg: :cyan, modifiers: [:bold]}
    }

    checkboxes =
      state.settings
      |> Enum.with_index()
      |> Enum.map(fn {setting, idx} ->
        selected? = idx == state.cursor

        label_style =
          if selected?,
            do: %Style{fg: :white, modifiers: [:bold]},
            else: %Style{fg: :white}

        checked_style =
          if setting.checked,
            do: %Style{fg: :green, modifiers: [:bold]},
            else: %Style{fg: :dark_gray}

        label = if selected?, do: "> #{setting.label}", else: "  #{setting.label}"

        checkbox = %Checkbox{
          label: label,
          checked: setting.checked,
          style: label_style,
          checked_style: checked_style
        }

        {checkbox, Enum.at(areas, idx + 1)}
      end)

    help = %Paragraph{
      text: "  Up/Down = move   Space = toggle   q = quit",
      style: %Style{fg: :dark_gray}
    }

    [{header, Enum.at(areas, 0)} | checkboxes] ++ [{help, List.last(areas)}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["Down", "j"] do
    {:noreply, %{state | cursor: rem(state.cursor + 1, length(state.settings))}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["Up", "k"] do
    {:noreply,
     %{state | cursor: rem(state.cursor - 1 + length(state.settings), length(state.settings))}}
  end

  def handle_event(%Event.Key{code: " ", kind: "press"}, state) do
    settings =
      List.update_at(state.settings, state.cursor, fn s -> %{s | checked: not s.checked} end)

    {:noreply, %{state | settings: settings}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = CheckboxDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
