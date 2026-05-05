defmodule ExRatatui.CellSession.Cell do
  @moduledoc """
  A single rendered cell of an `ExRatatui.CellSession`'s buffer.

  This is the post-render shape ratatui leaves in the cell at a given
  position — symbol, foreground/background colors, modifier set, and a
  `:skip` flag carrying ratatui's internal "do not render this cell"
  hint (used by widgets that overlay on top of others).

  ## Fields

    * `:row` — zero-indexed row (y coordinate in ratatui's terms)
    * `:col` — zero-indexed column (x coordinate)
    * `:symbol` — the grapheme cluster painted into the cell. Usually a
      single character but may be multi-codepoint (CJK ideographs,
      emoji, combining marks, box-drawing). Wide-display graphemes
      (e.g. `"中"`, `"🎉"`) live in their leading cell only — the
      following cell stays at its prior content (typically `" "`).
      Consumers reconstructing a faithful display should detect wide
      graphemes by computing display width and treat the next
      `width - 1` cells as covered.
    * `:fg` — foreground `t:ExRatatui.Style.color/0`. `:reset` means
      "use the consumer's default" (terminal default in a terminal,
      CSS default in a browser, "ink" on a 1-bit display).
    * `:bg` — background `t:ExRatatui.Style.color/0`, same conventions.
    * `:modifiers` — list of `t:ExRatatui.Style.modifier/0` atoms, in
      a stable sorted order (`:bold, :dim, :italic, :underlined,
      :crossed_out, :reversed`). Two cells with the same modifier set
      always produce equal lists, so consumers can compare with `==`.
    * `:skip` — ratatui's "do not render" flag. `false` for ordinary
      cells; widgets like `Popup` may set it to `true` on cells they
      want left alone. Browser/framebuffer renderers should treat
      `skip: true` as transparent (do nothing).

  ## Examples

      iex> %ExRatatui.CellSession.Cell{}
      %ExRatatui.CellSession.Cell{
        row: 0, col: 0, symbol: " ",
        fg: :reset, bg: :reset, modifiers: [], skip: false
      }
  """

  alias ExRatatui.Style

  defstruct row: 0, col: 0, symbol: " ", fg: :reset, bg: :reset, modifiers: [], skip: false

  @type t :: %__MODULE__{
          row: non_neg_integer(),
          col: non_neg_integer(),
          symbol: String.t(),
          fg: Style.color(),
          bg: Style.color(),
          modifiers: [Style.modifier()],
          skip: boolean()
        }

  @doc """
  Builds a `t:t/0` from the raw `{x, y, symbol, fg, bg, modifiers, skip}`
  tuple the NIF returns.

  Used internally by `ExRatatui.CellSession.Snapshot.from_native/1` and
  `ExRatatui.CellSession.Diff.from_native/1`. Exposed `pub` rather than
  `pub(private)` so consumers writing custom NIF-driven flows can
  reuse the conversion without re-implementing it.

  Note: the NIF's tuple uses `(x, y)` (column, row) order — matching
  ratatui's coordinate convention — while the struct uses `:row`/`:col`
  fields to match the rest of the project's vocabulary
  (`ExRatatui.Event.Mouse`, etc.).

  ## Examples

      iex> tuple = {3, 1, "X", :red, :reset, [:bold], false}
      iex> ExRatatui.CellSession.Cell.from_tuple(tuple)
      %ExRatatui.CellSession.Cell{
        row: 1, col: 3, symbol: "X",
        fg: :red, bg: :reset, modifiers: [:bold], skip: false
      }
  """
  @spec from_tuple(
          {non_neg_integer(), non_neg_integer(), String.t(), Style.color(), Style.color(),
           [Style.modifier()], boolean()}
        ) ::
          t()
  def from_tuple({col, row, symbol, fg, bg, modifiers, skip}) do
    %__MODULE__{
      row: row,
      col: col,
      symbol: symbol,
      fg: fg,
      bg: bg,
      modifiers: modifiers,
      skip: skip
    }
  end
end
