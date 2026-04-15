defmodule ExRatatui.Text do
  @moduledoc """
  Rich-text value composed of one or more `ExRatatui.Text.Line`s.

  `Text` mirrors ratatui's `Text` type: a list of lines with an optional
  top-level style and alignment. Styles cascade from the outermost layer
  inward (widget → Text → Line → Span); innermost values win on conflict.
  Per-line alignment (when set) overrides the widget's default alignment
  for that line.

  Used as the expanded form behind widget fields that accept rich text
  (`Paragraph.text`, `List.items`, `Table` cells, and — via
  `ExRatatui.Text.Line` — `Tabs.titles` and `Block.title`).

  ## Fields

    * `:lines` - list of `%ExRatatui.Text.Line{}`
    * `:style` - `%ExRatatui.Style{}` applied as the outermost default style
    * `:alignment` - `:left`, `:center`, `:right`, or `nil` (inherit from widget)

  ## Examples

      iex> alias ExRatatui.Text
      iex> alias ExRatatui.Text.{Line, Span}
      iex> alias ExRatatui.Style
      iex> Text.new([
      ...>   Line.new([Span.new("Hello ", style: %Style{fg: :green}), Span.new("world")]),
      ...>   Line.new([Span.new("Second line")])
      ...> ])
      %ExRatatui.Text{
        lines: [
          %ExRatatui.Text.Line{
            spans: [
              %ExRatatui.Text.Span{
                content: "Hello ",
                style: %ExRatatui.Style{fg: :green, bg: nil, modifiers: []}
              },
              %ExRatatui.Text.Span{content: "world", style: %ExRatatui.Style{}}
            ],
            style: %ExRatatui.Style{},
            alignment: nil
          },
          %ExRatatui.Text.Line{
            spans: [%ExRatatui.Text.Span{content: "Second line", style: %ExRatatui.Style{}}],
            style: %ExRatatui.Style{},
            alignment: nil
          }
        ],
        style: %ExRatatui.Style{},
        alignment: nil
      }
  """

  alias ExRatatui.Style
  alias ExRatatui.Text.Line

  @type alignment :: :left | :center | :right | nil

  @type t :: %__MODULE__{
          lines: [Line.t()],
          style: Style.t(),
          alignment: alignment()
        }

  defstruct lines: [], style: %Style{}, alignment: nil

  @doc """
  Builds a `%Text{}` from a list of lines and options.

  Options:

    * `:style` - a `%ExRatatui.Style{}` (default: `%Style{}`)
    * `:alignment` - `:left`, `:center`, `:right`, or `nil` (default: `nil`)

  Raises `ArgumentError` for an invalid `:alignment` value.
  """
  @spec new([Line.t()], keyword()) :: t()
  def new(lines, opts \\ []) when is_list(lines) do
    alignment = Keyword.get(opts, :alignment, nil)
    validate_alignment!(alignment)

    %__MODULE__{
      lines: lines,
      style: Keyword.get(opts, :style, %Style{}),
      alignment: alignment
    }
  end

  defp validate_alignment!(nil), do: :ok
  defp validate_alignment!(:left), do: :ok
  defp validate_alignment!(:center), do: :ok
  defp validate_alignment!(:right), do: :ok

  defp validate_alignment!(other) do
    raise ArgumentError,
          "invalid alignment: #{inspect(other)} (expected :left, :center, :right, or nil)"
  end
end
