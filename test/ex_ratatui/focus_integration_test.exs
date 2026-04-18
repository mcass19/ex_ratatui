defmodule ExRatatui.FocusIntegrationTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event
  alias ExRatatui.Focus
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, List, TextInput}

  # A tiny two-panel "app" — a TextInput and a List — sharing a Focus.
  # Keystrokes that aren't consumed by Focus are routed to the currently
  # focused widget. The test drives the same dispatcher the guide
  # documents.
  defp new_state do
    %{
      focus: Focus.new([:input, :list]),
      input: ExRatatui.text_input_new(),
      items: ["Alpha", "Beta", "Gamma"],
      selected: 0
    }
  end

  defp handle_key(state, %Event.Key{} = key) do
    {focus, key} = Focus.handle_key(state.focus, key)
    state = %{state | focus: focus}

    case key do
      nil ->
        state

      key ->
        case Focus.current(focus) do
          :input -> dispatch_input(state, key)
          :list -> dispatch_list(state, key)
        end
    end
  end

  defp dispatch_input(state, %Event.Key{code: code}) do
    :ok = ExRatatui.text_input_handle_key(state.input, code)
    state
  end

  defp dispatch_list(state, %Event.Key{code: "down"} = _key) do
    %{state | selected: min(state.selected + 1, length(state.items) - 1)}
  end

  defp dispatch_list(state, %Event.Key{code: "up"} = _key) do
    %{state | selected: max(state.selected - 1, 0)}
  end

  defp dispatch_list(state, _key), do: state

  defp render(state) do
    terminal = ExRatatui.init_test_terminal(30, 6)

    input_widget = %TextInput{
      state: state.input,
      block: %Block{
        title: "Search",
        borders: [:all],
        border_style:
          if(Focus.focused?(state.focus, :input),
            do: %ExRatatui.Style{fg: :yellow},
            else: %ExRatatui.Style{}
          )
      }
    }

    list_widget = %List{
      items: state.items,
      selected: state.selected,
      highlight_symbol: "> ",
      block: %Block{
        title: "Items",
        borders: [:all],
        border_style:
          if(Focus.focused?(state.focus, :list),
            do: %ExRatatui.Style{fg: :yellow},
            else: %ExRatatui.Style{}
          )
      }
    }

    :ok =
      ExRatatui.draw(terminal, [
        {input_widget, %Rect{x: 0, y: 0, width: 30, height: 3}},
        {list_widget, %Rect{x: 0, y: 3, width: 30, height: 3}}
      ])

    ExRatatui.get_buffer_content(terminal)
  end

  test "keystrokes only reach the focused widget" do
    state =
      new_state()
      # focus starts on :input — "a" goes to the text input
      |> handle_key(%Event.Key{code: "a"})
      |> handle_key(%Event.Key{code: "b"})
      # "down" on :input widens/no-ops the input — it's a valid TextInput key
      # but doesn't change the text, so value is still "ab"
      |> handle_key(%Event.Key{code: "tab"})
      # now focused on :list — arrow keys move selection, typing a char is a no-op
      |> handle_key(%Event.Key{code: "down"})
      |> handle_key(%Event.Key{code: "z"})

    assert Focus.current(state.focus) == :list
    assert state.selected == 1
    assert ExRatatui.text_input_get_value(state.input) == "ab"
  end

  test "Shift+Tab cycles focus backward through the ring" do
    state =
      new_state()
      |> handle_key(%Event.Key{code: "tab", modifiers: ["shift"]})

    assert Focus.current(state.focus) == :list

    state = handle_key(state, %Event.Key{code: "tab", modifiers: ["shift"]})
    assert Focus.current(state.focus) == :input
  end

  test "rendering reflects the focused widget and typed input" do
    state =
      new_state()
      |> handle_key(%Event.Key{code: "h"})
      |> handle_key(%Event.Key{code: "i"})
      |> handle_key(%Event.Key{code: "tab"})
      |> handle_key(%Event.Key{code: "down"})

    buffer = render(state)

    # Both widgets present
    assert buffer =~ "Search"
    assert buffer =~ "Items"
    # TextInput rendered the typed characters
    assert buffer =~ "hi"
    # List selection is on the second item
    assert buffer =~ "> Beta"
  end
end
