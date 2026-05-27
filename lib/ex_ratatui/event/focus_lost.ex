defmodule ExRatatui.Event.FocusLost do
  @moduledoc """
  Emitted when the terminal window loses focus.

  Carries no payload — pattern-match the struct itself. Apps use this
  to pause expensive animations or background ticks while the user is
  elsewhere; see `ExRatatui.Event.FocusGained` for the inverse and a
  full pattern-match example.
  """

  @type t :: %__MODULE__{}

  defstruct []
end
