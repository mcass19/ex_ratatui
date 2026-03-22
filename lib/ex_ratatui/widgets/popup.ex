defmodule ExRatatui.Widgets.Popup do
  @moduledoc """
  A centered modal overlay widget.

  Renders a widget centered over the parent area, clearing the background
  underneath. Useful for dialogs, confirmations, command palettes, and
  autocomplete popups.

  The popup size can be specified as a percentage of the parent area or
  as fixed dimensions. Fixed dimensions take precedence when set.

  ## Examples

      iex> alias ExRatatui.Widgets.{Popup, Paragraph, Block}
      iex> %Popup{
      ...>   content: %Paragraph{text: "Are you sure?"},
      ...>   block: %Block{title: "Confirm", borders: [:all], border_type: :rounded},
      ...>   percent_width: 50,
      ...>   percent_height: 30
      ...> }
  """

  @type t :: %__MODULE__{
          content: ExRatatui.widget() | nil,
          block: ExRatatui.Widgets.Block.t() | nil,
          percent_width: non_neg_integer(),
          percent_height: non_neg_integer(),
          fixed_width: non_neg_integer() | nil,
          fixed_height: non_neg_integer() | nil
        }

  defstruct content: nil,
            block: nil,
            percent_width: 60,
            percent_height: 60,
            fixed_width: nil,
            fixed_height: nil
end
