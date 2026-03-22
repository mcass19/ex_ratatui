defmodule ExRatatui.Widgets.Markdown do
  @moduledoc """
  A markdown rendering widget with syntax highlighting for code blocks.

  Uses the `tui-markdown` Rust crate (powered by `pulldown-cmark` + `syntect`)
  to parse markdown and render it with styled text spans. Supports headings,
  bold, italic, inline code, fenced code blocks with syntax highlighting,
  bullet lists, links, and horizontal rules.

  Ideal for rendering AI assistant responses in a chat interface.

  ## Examples

      %Markdown{
        content: "# Hello\\n\\nSome **bold** text and `code`.",
        block: %Block{title: "Response", borders: [:all]}
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
