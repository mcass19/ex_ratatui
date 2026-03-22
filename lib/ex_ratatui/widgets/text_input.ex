defmodule ExRatatui.Widgets.TextInput do
  @moduledoc """
  A single-line text input widget with cursor and viewport management.

  TextInput is the first **stateful** widget in ExRatatui — its internal state
  (text value, cursor position, viewport scroll) lives in Rust via ResourceArc.
  You create a state reference with `ExRatatui.text_input_new/0` and pass it
  as the `:state` field.

  ## State Management

      # Create a new input state (returns a reference)
      state = ExRatatui.text_input_new()

      # Forward key events to the input
      ExRatatui.text_input_handle_key(state, "h")
      ExRatatui.text_input_handle_key(state, "i")

      # Read the current value
      ExRatatui.text_input_get_value(state)  #=> "hi"

      # Set value programmatically
      ExRatatui.text_input_set_value(state, "hello")

  ## Supported Keys

  Pass the key code string from `ExRatatui.Event.Key` to `text_input_handle_key/2`:

    * Printable characters — inserted at cursor
    * `"backspace"` — delete character before cursor
    * `"delete"` — delete character at cursor
    * `"left"` / `"right"` — move cursor
    * `"home"` / `"end"` — jump to start / end

  ## Fields

    * `:state` - the input state reference from `ExRatatui.text_input_new/0` (required)
    * `:style` - `%ExRatatui.Style{}` for the text
    * `:cursor_style` - `%ExRatatui.Style{}` for the cursor character (typically reversed)
    * `:placeholder` - optional placeholder text shown when the input is empty
    * `:placeholder_style` - `%ExRatatui.Style{}` for the placeholder text
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container

  ## Examples

      state = ExRatatui.text_input_new()

      %ExRatatui.Widgets.TextInput{
        state: state,
        style: %ExRatatui.Style{fg: :white},
        cursor_style: %ExRatatui.Style{fg: :black, bg: :white},
        placeholder: "Type here...",
        placeholder_style: %ExRatatui.Style{fg: :dark_gray},
        block: %ExRatatui.Widgets.Block{
          title: "Search",
          borders: [:all],
          border_type: :rounded
        }
      }
  """

  @type t :: %__MODULE__{
          state: reference() | nil,
          style: ExRatatui.Style.t(),
          cursor_style: ExRatatui.Style.t(),
          placeholder: String.t() | nil,
          placeholder_style: ExRatatui.Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct state: nil,
            style: %ExRatatui.Style{},
            cursor_style: %ExRatatui.Style{},
            placeholder: nil,
            placeholder_style: %ExRatatui.Style{},
            block: nil
end
