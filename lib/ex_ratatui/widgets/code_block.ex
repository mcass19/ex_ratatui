defmodule ExRatatui.Widgets.CodeBlock do
  @moduledoc """
  A syntax-highlighted code display widget.

  Powered by `syntect`, shares its syntax/theme machinery with
  `ExRatatui.Widgets.Markdown`. Supports the seven themes bundled with
  syntect plus any string a custom theme set understands. See
  `ExRatatui.CodeBlock` for the bundled language set (syntect's defaults
  plus Elixir).

  Ideal for static code samples, slide decks, tutorials, and any
  read-only code view. For editable code, use `ExRatatui.Widgets.Textarea`
  (highlighted editing is a future feature).

  ## Fields

    * `:content` — source code string
    * `:language` — syntect token name (e.g. `"elixir"`, `"rust"`, `"python"`)
      or `nil` for plain text
    * `:theme` — atom (curated) or raw string; see "Themes" below
    * `:line_numbers` — `true` to render a right-aligned gutter before each
      line (default: `false`)
    * `:starting_line` — first line number when `:line_numbers` is `true`
      (default: `1`)
    * `:highlight_lines` — list of line numbers and/or ranges to emphasise
      with a subtle theme-derived background. Example: `[3, 7..9]`.
      Numbers are 1-based and refer to the rendered line number (so they
      pair with `:starting_line` when offsets are in play).
    * `:style` — `%ExRatatui.Style{}` for the widget background
    * `:block` — optional `%ExRatatui.Widgets.Block{}` container
    * `:scroll` — `{vertical, horizontal}` scroll offset (default: `{0, 0}`)
    * `:wrap` — `true` to wrap long lines (default: `false` — code rarely
      wants soft-wrap)

  ## Themes

  Curated atoms resolve to syntect's bundled `ThemeSet`:

    * `:base16_ocean_dark` (default)
    * `:base16_ocean_light`
    * `:base16_eighties_dark`
    * `:base16_mocha_dark`
    * `:inspired_github`
    * `:solarized_dark`
    * `:solarized_light`

  Raw strings pass through unchanged for users who load their own theme
  sets.

  ## Examples

      iex> %ExRatatui.Widgets.CodeBlock{content: "IO.puts(\\"hi\\")", language: "elixir"}
      %ExRatatui.Widgets.CodeBlock{
        content: "IO.puts(\\"hi\\")",
        language: "elixir",
        theme: :base16_ocean_dark,
        line_numbers: false,
        starting_line: 1,
        highlight_lines: [],
        style: %ExRatatui.Style{},
        block: nil,
        scroll: {0, 0},
        wrap: false
      }

      iex> alias ExRatatui.Widgets.{CodeBlock, Block}
      iex> code = %CodeBlock{
      ...>   content: "fn main() {}",
      ...>   language: "rust",
      ...>   theme: :solarized_dark,
      ...>   block: %Block{title: "main.rs", borders: [:all]}
      ...> }
      iex> code.theme
      :solarized_dark

      iex> %ExRatatui.Widgets.CodeBlock{content: "", theme: "InspiredGitHub"}.theme
      "InspiredGitHub"
  """

  alias ExRatatui.Style

  @type theme ::
          :base16_ocean_dark
          | :base16_ocean_light
          | :base16_eighties_dark
          | :base16_mocha_dark
          | :inspired_github
          | :solarized_dark
          | :solarized_light
          | String.t()

  @type highlight_entry :: pos_integer() | Range.t()

  @type t :: %__MODULE__{
          content: String.t(),
          language: String.t() | nil,
          theme: theme(),
          line_numbers: boolean(),
          starting_line: pos_integer(),
          highlight_lines: [highlight_entry()],
          style: Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil,
          scroll: {non_neg_integer(), non_neg_integer()},
          wrap: boolean()
        }

  defstruct content: "",
            language: nil,
            theme: :base16_ocean_dark,
            line_numbers: false,
            starting_line: 1,
            highlight_lines: [],
            style: %Style{},
            block: nil,
            scroll: {0, 0},
            wrap: false
end
