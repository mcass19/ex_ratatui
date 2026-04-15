defmodule ExRatatui.Text.Line do
  @moduledoc """
  A single line of text composed of one or more `ExRatatui.Text.Span`s.

  A line may carry its own style (merged over any parent `Text`/widget style)
  and its own alignment, which overrides the widget's default alignment for
  that line when set.

  ## Fields

    * `:spans` - list of `%ExRatatui.Text.Span{}`
    * `:style` - `%ExRatatui.Style{}` applied to the line (layered with Span styles)
    * `:alignment` - `:left`, `:center`, `:right`, or `nil` (inherit)

  ## Examples

      iex> alias ExRatatui.Text.{Line, Span}
      iex> alias ExRatatui.Style
      iex> Line.new([Span.new("Hello "), Span.new("world", style: %Style{fg: :green})])
      %ExRatatui.Text.Line{
        spans: [
          %ExRatatui.Text.Span{content: "Hello ", style: %ExRatatui.Style{}},
          %ExRatatui.Text.Span{
            content: "world",
            style: %ExRatatui.Style{fg: :green, bg: nil, modifiers: []}
          }
        ],
        style: %ExRatatui.Style{},
        alignment: nil
      }

      iex> alias ExRatatui.Text.{Line, Span}
      iex> alias ExRatatui.Style
      iex> Line.new([Span.new("centered")], style: %Style{modifiers: [:bold]}, alignment: :center)
      %ExRatatui.Text.Line{
        spans: [%ExRatatui.Text.Span{content: "centered", style: %ExRatatui.Style{}}],
        style: %ExRatatui.Style{fg: nil, bg: nil, modifiers: [:bold]},
        alignment: :center
      }
  """

  alias ExRatatui.Style
  alias ExRatatui.Text.Span

  @type alignment :: :left | :center | :right | nil

  @type t :: %__MODULE__{
          spans: [Span.t()],
          style: Style.t(),
          alignment: alignment()
        }

  defstruct spans: [], style: %Style{}, alignment: nil

  @doc """
  Builds a `%Line{}` from a list of spans and options.

  Options:

    * `:style` - a `%ExRatatui.Style{}` (default: `%Style{}`)
    * `:alignment` - `:left`, `:center`, `:right`, or `nil` (default: `nil`)

  Raises `ArgumentError` for an invalid `:alignment` value.
  """
  @spec new([Span.t()], keyword()) :: t()
  def new(spans, opts \\ []) when is_list(spans) do
    alignment = Keyword.get(opts, :alignment, nil)
    validate_alignment!(alignment)

    %__MODULE__{
      spans: spans,
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
