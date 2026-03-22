defmodule ExRatatui.Widgets.Textarea do
  @moduledoc """
  A multiline text editor widget with undo/redo, cursor movement, and selection.

  Uses the `ratatui-textarea` Rust crate. State lives in Rust via ResourceArc —
  create it with `ExRatatui.textarea_new/0` and pass the reference as `:state`.

  ## Usage

      state = ExRatatui.textarea_new()
      ExRatatui.textarea_handle_key(state, "h", [])
      ExRatatui.textarea_handle_key(state, "i", [])
      ExRatatui.textarea_get_value(state)  # => "hi"

      %Textarea{state: state, block: %Block{title: "Message", borders: [:all]}}

  ## Key handling

  Forward key events via `ExRatatui.textarea_handle_key/3`. The textarea
  supports Emacs-style shortcuts by default:

    * `Ctrl+Z` — undo
    * `Ctrl+Y` — redo
    * `Ctrl+A` / `Home` — beginning of line
    * `Ctrl+E` / `End` — end of line
    * `Ctrl+K` — delete to end of line
    * `Ctrl+W` — delete word backward
    * Arrow keys, Page Up/Down, etc.

  ## Enter vs Submit

  The textarea always inserts newlines on Enter. To implement "Enter = submit,
  Shift+Enter = newline", intercept Enter in your App's `handle_event` before
  forwarding to the textarea.

  ## Examples

      iex> alias ExRatatui.Widgets.Textarea
      iex> %Textarea{} = %Textarea{}
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
