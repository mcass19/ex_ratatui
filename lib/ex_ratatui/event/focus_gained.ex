defmodule ExRatatui.Event.FocusGained do
  @moduledoc """
  Emitted when the terminal window gains focus.

  Carries no payload — pattern-match the struct itself. Apps use this
  to resume animations, refresh stale data, or restore a polished idle
  state when the user returns to the terminal.

  Focus reporting is enabled automatically by `ExRatatui.run/1` via
  crossterm's `EnableFocusChange`. Terminals that don't support focus
  reporting silently ignore the request and no Focus events arrive —
  apps don't need a conditional path.

  Companion: `ExRatatui.Event.FocusLost`.

  ## Example

      case ExRatatui.poll_event(timeout) do
        %ExRatatui.Event.FocusGained{} ->
          %{state | spinner_active: true}

        %ExRatatui.Event.FocusLost{} ->
          %{state | spinner_active: false}

        _ ->
          state
      end
  """

  @type t :: %__MODULE__{}

  defstruct []
end
