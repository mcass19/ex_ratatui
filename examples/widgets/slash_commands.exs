# Example: SlashCommands — autocomplete a "/command" as it is typed.
# Run with: mix run examples/widgets/slash_commands.exs
#
# Controls: type "/" to trigger autocomplete, Up/Down = select,
#           Enter/Tab = complete, Esc = dismiss, q = quit (when input empty)

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph, TextInput}
alias ExRatatui.Widgets.SlashCommands
alias ExRatatui.Widgets.SlashCommands.Command

defmodule SlashCommandsDemo do
  use ExRatatui.App

  @commands [
    %Command{name: "help", description: "Show available commands"},
    %Command{name: "clear", description: "Clear the screen"},
    %Command{name: "model", description: "Switch model"},
    %Command{name: "system", description: "Set system prompt"},
    %Command{name: "quit", description: "Exit", aliases: ["exit", "q"]}
  ]

  @impl true
  def mount(_opts) do
    {:ok, %{input: ExRatatui.text_input_new(), show: false, matches: [], selected: 0}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [input_area, help_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}])

    input = %TextInput{
      state: state.input,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      placeholder: "Type / to see commands...",
      placeholder_style: %Style{fg: :dark_gray},
      block: %Block{
        title: " Command ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    help = %Paragraph{
      text:
        "  Type \"/\" to trigger autocomplete.\n" <>
          "  Up/Down = select   Enter/Tab = complete   Esc = dismiss\n" <>
          "  q = quit (when the input is empty)",
      style: %Style{fg: :dark_gray}
    }

    widgets = [{input, input_area}, {help, help_area}]

    if state.show and state.matches != [] do
      popup =
        SlashCommands.render_autocomplete(state.matches,
          area: area,
          selected: state.selected,
          percent_width: 40,
          percent_height: 30,
          highlight_style: %Style{fg: :black, bg: :cyan, modifiers: [:bold]}
        )

      popup ++ widgets
    else
      widgets
    end
  end

  @impl true
  def handle_event(%Event.Key{code: "c", modifiers: ["ctrl"], kind: "press"}, state),
    do: {:stop, state}

  def handle_event(%Event.Key{code: "escape", kind: "press"}, state),
    do: {:noreply, %{state | show: false}}

  def handle_event(%Event.Key{code: code, kind: "press"}, %{show: true} = state)
      when code in ["up", "down"] do
    delta = if code == "down", do: 1, else: -1
    max_index = max(0, length(state.matches) - 1)
    {:noreply, %{state | selected: clamp(state.selected + delta, 0, max_index)}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, %{show: true} = state)
      when code in ["enter", "tab"] do
    case Enum.at(state.matches, state.selected) do
      %Command{name: name} ->
        ExRatatui.text_input_set_value(state.input, "/#{name} ")
        {:noreply, %{state | show: false, matches: []}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    value = ExRatatui.text_input_get_value(state.input)

    if value == "" and not state.show do
      {:stop, state}
    else
      ExRatatui.text_input_handle_key(state.input, "q")
      {:noreply, refresh_autocomplete(state)}
    end
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) do
    ExRatatui.text_input_handle_key(state.input, code)
    {:noreply, refresh_autocomplete(state)}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp refresh_autocomplete(state) do
    value = ExRatatui.text_input_get_value(state.input)

    case SlashCommands.parse(value) do
      {:command, prefix} ->
        matches = SlashCommands.match_commands(@commands, prefix)
        %{state | show: matches != [], matches: matches, selected: 0}

      :no_command ->
        %{state | show: false, matches: []}
    end
  end

  defp clamp(value, min, max), do: value |> max(min) |> min(max)
end

{:ok, pid} = SlashCommandsDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
