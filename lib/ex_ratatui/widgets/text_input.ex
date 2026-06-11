defmodule ExRatatui.Widgets.TextInput do
  @moduledoc """
  A single-line text input widget with cursor and viewport management.

  TextInput is the first **stateful** widget in ExRatatui — its internal state
  (text value, cursor position, viewport scroll) lives in Rust via ResourceArc.
  Create a state reference with `ExRatatui.text_input_new/0` and pass it
  as the `:state` field.

  ## State Management

  The state reference is an opaque handle to Rust-side memory. Treat it
  like any other NIF resource:

    * Don't serialize, persist, or compare it with `==`.
    * Don't send it to another BEAM node — ResourceArcs are node-local.
      The distributed transport snapshots stateful widgets into plain
      terms before shipping them; reconstruct state on the client side
      rather than forwarding the reference.
    * A reference is garbage-collected when no process holds it.

  ```elixir
  # Create a new input state (returns a reference)
  state = ExRatatui.text_input_new()

  # Forward key events to the input
  ExRatatui.text_input_handle_key(state, "h")
  ExRatatui.text_input_handle_key(state, "i")

  # Read the current value
  ExRatatui.text_input_get_value(state)  #=> "hi"

  # Set value programmatically
  ExRatatui.text_input_set_value(state, "hello")
  ```

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

      iex> %ExRatatui.Widgets.TextInput{}
      %ExRatatui.Widgets.TextInput{
        state: nil,
        style: %ExRatatui.Style{},
        cursor_style: %ExRatatui.Style{},
        placeholder: nil,
        placeholder_style: %ExRatatui.Style{},
        block: nil
      }

      iex> alias ExRatatui.Widgets.{TextInput, Block}
      iex> alias ExRatatui.Style
      iex> %TextInput{
      ...>   placeholder: "Type here...",
      ...>   placeholder_style: %Style{fg: :dark_gray},
      ...>   block: %Block{title: "Search", borders: [:all], border_type: :rounded}
      ...> }
      %ExRatatui.Widgets.TextInput{
        state: nil,
        style: %ExRatatui.Style{},
        cursor_style: %ExRatatui.Style{},
        placeholder: "Type here...",
        placeholder_style: %ExRatatui.Style{fg: :dark_gray},
        block: %ExRatatui.Widgets.Block{title: "Search", borders: [:all], border_type: :rounded}
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
