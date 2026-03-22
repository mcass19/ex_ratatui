defmodule ExRatatui.Widgets.Checkbox do
  @moduledoc """
  A checkbox widget for toggling boolean values.

  Renders a checkbox symbol followed by a label. Useful for yes/no toggles,
  multi-select option lists, and boolean prompts.

  ## Fields

    * `:label` - the text displayed next to the checkbox
    * `:checked` - whether the checkbox is checked (default: `false`)
    * `:style` - `%ExRatatui.Style{}` for the label text
    * `:checked_style` - `%ExRatatui.Style{}` for the checkbox symbol
    * `:checked_symbol` - custom string for the checked state (default: `"[x]"`)
    * `:unchecked_symbol` - custom string for the unchecked state (default: `"[ ]"`)
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container

  ## Examples

      iex> %ExRatatui.Widgets.Checkbox{label: "Enable notifications", checked: true}
      %ExRatatui.Widgets.Checkbox{
        label: "Enable notifications",
        checked: true,
        style: %ExRatatui.Style{},
        checked_style: %ExRatatui.Style{},
        checked_symbol: nil,
        unchecked_symbol: nil,
        block: nil
      }
  """

  @type t :: %__MODULE__{
          label: String.t(),
          checked: boolean(),
          style: ExRatatui.Style.t(),
          checked_style: ExRatatui.Style.t(),
          checked_symbol: String.t() | nil,
          unchecked_symbol: String.t() | nil,
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct label: "",
            checked: false,
            style: %ExRatatui.Style{},
            checked_style: %ExRatatui.Style{},
            checked_symbol: nil,
            unchecked_symbol: nil,
            block: nil
end
