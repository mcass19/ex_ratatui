defmodule ExRatatui.Event do
  @moduledoc """
  Terminal event structs.

  Events are returned by `ExRatatui.poll_event/1` and can be pattern matched
  to handle user input:

    * `ExRatatui.Event.Key` — keyboard events (key presses, releases, repeats)
    * `ExRatatui.Event.Mouse` — mouse events (clicks, scrolls, drags)
    * `ExRatatui.Event.Resize` — terminal resize events
    * `ExRatatui.Event.Paste` — bracketed-paste events with the full
      pasted payload

  ## Example

      case ExRatatui.poll_event(timeout) do
        %ExRatatui.Event.Key{code: "q"} -> :quit
        %ExRatatui.Event.Key{code: "up"} -> :scroll_up
        %ExRatatui.Event.Mouse{kind: "scroll_down"} -> :scroll_down
        %ExRatatui.Event.Resize{width: w, height: h} -> {:resize, w, h}
        %ExRatatui.Event.Paste{content: text} -> {:paste, text}
        nil -> :no_event
      end
  """

  @type t ::
          ExRatatui.Event.Key.t()
          | ExRatatui.Event.Mouse.t()
          | ExRatatui.Event.Resize.t()
          | ExRatatui.Event.Paste.t()
end
