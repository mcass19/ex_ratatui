defmodule ExRatatui.Widgets.Block.Title do
  @moduledoc """
  A single title entry inside a `%ExRatatui.Widgets.Block{}`.

  Blocks can carry any number of titles, each anchored to the top or
  bottom border and aligned left, center, or right. The classic
  "filename | scroll %" header is two titles on the top border with
  opposite alignments.

  ## Fields

    * `:content` — any `ExRatatui.Text`-coercible line-like value:
      a `String.t()`, `%Span{}`, `%Line{}`, or a list of spans.
      Multi-line content raises.
    * `:position` — `:top`, `:bottom`, or `nil` (falls back to the
      block's `:title_position`, which defaults to `:top`).
    * `:alignment` — `:left`, `:center`, `:right`, or `nil` (falls
      back to the block's `:title_alignment`, which defaults to
      `:left`).
    * `:style` — `%ExRatatui.Style{}` or `nil`. When `nil`, the
      block's `:title_style` applies.

  ## Examples

      iex> alias ExRatatui.Widgets.Block.Title
      iex> %Title{content: "Search", alignment: :left}
      %ExRatatui.Widgets.Block.Title{
        content: "Search",
        position: nil,
        alignment: :left,
        style: nil
      }
  """

  alias ExRatatui.Style

  @type position :: :top | :bottom | nil
  @type alignment :: :left | :center | :right | nil

  @type content ::
          String.t()
          | ExRatatui.Text.Span.t()
          | ExRatatui.Text.Line.t()
          | [ExRatatui.Text.Span.t()]

  @type t :: %__MODULE__{
          content: content(),
          position: position(),
          alignment: alignment(),
          style: Style.t() | nil
        }

  defstruct content: nil, position: nil, alignment: nil, style: nil
end
