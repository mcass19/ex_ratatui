defmodule ExRatatui.Event.Paste do
  @moduledoc """
  A bracketed-paste event.

  Emitted when the terminal is in bracketed-paste mode and a user pastes
  content (typically via Ctrl+Shift+V, Cmd+V, or middle-click). The full
  pasted payload arrives as one event rather than as a stream of
  individual Key events, preserving newlines and protecting widgets from
  accidentally interpreting pasted control characters as commands.

  Bracketed paste is enabled automatically on the local terminal
  (`ExRatatui.init/0`); apps consuming events from the byte-stream
  Session, SSH, or distributed transports may not see Paste events
  unless the input parser on that transport has been taught to decode
  the `ESC[200~ ... ESC[201~` markers.

  ## Fields

    * `:content` — the pasted text, with line breaks preserved as
      `\\n`. Control characters other than newline are passed through
      as-is; consumers may want to filter them depending on the target
      widget (single-line `TextInput` usually drops newlines; multi-line
      `Textarea` keeps them).

  ## Example

      case ExRatatui.poll_event(timeout) do
        %ExRatatui.Event.Paste{content: text} ->
          ExRatatui.textarea_insert_str(state.editor, text)

        %ExRatatui.Event.Key{code: "q"} ->
          :quit

        _ ->
          :continue
      end
  """

  @type t :: %__MODULE__{content: String.t()}

  defstruct [:content]
end
