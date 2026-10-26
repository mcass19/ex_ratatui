defmodule ExRatatui.Event.Key do
  @moduledoc """
  A keyboard event.

  ## Fields

    * `:code` - the key that was pressed, as a string (see Key Codes below)
    * `:kind` - `"press"`, `"release"`, or `"repeat"`. Terminals only report
      the last two when asked with `keyboard_enhancement: true`; see
      [Key releases](building_uis.html#key-releases)
    * `:modifiers` - list of active modifiers: `"shift"`, `"ctrl"`, `"alt"`,
      `"super"`, `"hyper"`, `"meta"`

  ## Key Codes

  Character keys are returned as their string value (`"a"`, `"z"`, `"1"`, `" "`, etc.).

  Special keys:

  | Code | Key |
  |------|-----|
  | `"enter"` | Enter / Return |
  | `"esc"` | Escape |
  | `"tab"` | Tab |
  | `"back_tab"` | Shift+Tab |
  | `"backspace"` | Backspace |
  | `"delete"` | Delete |
  | `"insert"` | Insert |
  | `"up"` | Arrow Up |
  | `"down"` | Arrow Down |
  | `"left"` | Arrow Left |
  | `"right"` | Arrow Right |
  | `"home"` | Home |
  | `"end"` | End |
  | `"page_up"` | Page Up |
  | `"page_down"` | Page Down |
  | `"f1"` .. `"f12"` | Function keys |
  | `"caps_lock"` | Caps Lock |
  | `"scroll_lock"` | Scroll Lock |
  | `"num_lock"` | Num Lock |
  | `"print_screen"` | Print Screen |
  | `"pause"` | Pause |
  | `"menu"` | Menu / Context |
  | `"keypad_begin"` | Keypad Begin (numpad 5) |

  ## Examples

      iex> %ExRatatui.Event.Key{code: "q", kind: "press"}
      %ExRatatui.Event.Key{code: "q", kind: "press", modifiers: []}

      iex> %ExRatatui.Event.Key{code: "c", kind: "press", modifiers: ["ctrl"]}
      %ExRatatui.Event.Key{code: "c", kind: "press", modifiers: ["ctrl"]}

  Pattern matching on events:

      # Match any arrow key
      %Event.Key{code: code, kind: "press"} when code in ~w(up down left right)
  """

  @type t :: %__MODULE__{
          code: String.t() | nil,
          modifiers: [String.t()],
          kind: String.t() | nil
        }

  defstruct [:code, :kind, modifiers: []]
end
