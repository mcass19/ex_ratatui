defmodule ExRatatui.Widgets.Markdown do
  @moduledoc """
  A markdown rendering widget with syntax highlighting for code blocks.

  Uses the `tui-markdown` Rust crate (powered by `pulldown-cmark` + `syntect`)
  to parse markdown and render it with styled text spans. Supports headings,
  bold, italic, inline code, fenced code blocks with syntax highlighting,
  bullet lists, links, and horizontal rules.

  Ideal for rendering AI assistant responses in a chat interface.

  Fenced-code highlighting uses syntect's bundled `base16-ocean.dark` theme,
  which is hardcoded by `tui-markdown` and cannot be overridden through its
  public API. For themed code display, use `ExRatatui.Widgets.CodeBlock`
  directly.

  ## Fields

    * `:content` - the markdown text to render
    * `:style` - `%ExRatatui.Style{}` for the widget background
    * `:block` - optional `%ExRatatui.Widgets.Block{}` container
    * `:scroll` - `{vertical, horizontal}` scroll offset (default: `{0, 0}`)
    * `:wrap` - `true` to wrap text at widget boundary (default: `true`)

  ## Examples

      iex> %ExRatatui.Widgets.Markdown{content: "# Hello\\n\\nSome **bold** text."}
      %ExRatatui.Widgets.Markdown{
        content: "# Hello\\n\\nSome **bold** text.",
        style: %ExRatatui.Style{},
        block: nil,
        scroll: {0, 0},
        wrap: true
      }

      iex> alias ExRatatui.Widgets.{Markdown, Block}
      iex> %Markdown{
      ...>   content: "Some text",
      ...>   block: %Block{title: "Response", borders: [:all]}
      ...> }
      %ExRatatui.Widgets.Markdown{
        content: "Some text",
        style: %ExRatatui.Style{},
        block: %ExRatatui.Widgets.Block{title: "Response", borders: [:all]},
        scroll: {0, 0},
        wrap: true
      }
  """

  alias ExRatatui.Style

  @type t :: %__MODULE__{
          content: String.t(),
          style: Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil,
          scroll: {non_neg_integer(), non_neg_integer()},
          wrap: boolean()
        }

  defstruct content: "",
            style: %Style{},
            block: nil,
            scroll: {0, 0},
            wrap: true
end
