defmodule ExRatatui.Widgets.Textarea do
  @moduledoc """
  A multiline text editor widget with undo/redo, cursor movement, and selection.

  Uses the `ratatui-textarea` Rust crate. State lives in Rust via ResourceArc —
  create it with `ExRatatui.textarea_new/0` and pass the reference as `:state`.

  The state reference is an opaque handle to Rust-side memory: don't
  serialize, persist, compare, or send it to another node. The
  distributed transport snapshots stateful widgets into plain terms
  before shipping them.

  ## Usage

      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "h", [])
      ExRatatui.textarea_handle_key(state, "i", [])
      ExRatatui.textarea_get_value(state)  # => "hi"

      %Textarea{state: state, block: %Block{title: "Message", borders: [:all]}}

  ## Key handling

  Forward key events via `ExRatatui.textarea_handle_key/3`. The textarea
  supports Emacs-style shortcuts by default:

    * `Ctrl+A` / `Home` — beginning of line
    * `Ctrl+E` / `End` — end of line
    * `Ctrl+K` — delete to end of line
    * `Ctrl+W` — delete word backward
    * Arrow keys, Page Up/Down, etc.

  ## Enter vs Submit

  The textarea always inserts newlines on Enter. To implement "Enter = submit,
  Shift+Enter = newline", intercept Enter in the App's `handle_event` before
  forwarding to the textarea.

  ## Examples

      iex> %ExRatatui.Widgets.Textarea{}
      %ExRatatui.Widgets.Textarea{
        state: nil,
        style: %ExRatatui.Style{},
        cursor_style: %ExRatatui.Style{},
        cursor_line_style: %ExRatatui.Style{},
        placeholder: nil,
        placeholder_style: %ExRatatui.Style{},
        line_number_style: nil,
        block: nil
      }

      iex> alias ExRatatui.Widgets.{Textarea, Block}
      iex> alias ExRatatui.Style
      iex> %Textarea{
      ...>   placeholder: "Type a message...",
      ...>   placeholder_style: %Style{fg: :dark_gray},
      ...>   block: %Block{title: "Message", borders: [:all]}
      ...> }
      %ExRatatui.Widgets.Textarea{
        state: nil,
        style: %ExRatatui.Style{},
        cursor_style: %ExRatatui.Style{},
        cursor_line_style: %ExRatatui.Style{},
        placeholder: "Type a message...",
        placeholder_style: %ExRatatui.Style{fg: :dark_gray},
        line_number_style: nil,
        block: %ExRatatui.Widgets.Block{title: "Message", borders: [:all]}
      }
  """

  alias ExRatatui.Style

  @type t :: %__MODULE__{
          state: reference() | nil,
          style: Style.t(),
          cursor_style: Style.t(),
          cursor_line_style: Style.t(),
          placeholder: String.t() | nil,
          placeholder_style: Style.t(),
          line_number_style: Style.t() | nil,
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct state: nil,
            style: %Style{},
            cursor_style: %Style{},
            cursor_line_style: %Style{},
            placeholder: nil,
            placeholder_style: %Style{},
            line_number_style: nil,
            block: nil
end
