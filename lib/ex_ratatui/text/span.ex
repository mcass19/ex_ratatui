defmodule ExRatatui.Text.Span do
  @moduledoc """
  A single styled run of text — the smallest rich-text primitive.

  A span is a single line of text with its own style. Spans are composed into
  `ExRatatui.Text.Line`s, which are composed into `ExRatatui.Text`.

  ## Fields

    * `:content` - the span's text (no embedded newlines)
    * `:style` - `%ExRatatui.Style{}` applied to the span

  ## Examples

      iex> alias ExRatatui.Text.Span
      iex> alias ExRatatui.Style
      iex> Span.new("hello")
      %ExRatatui.Text.Span{content: "hello", style: %ExRatatui.Style{}}

      iex> alias ExRatatui.Text.Span
      iex> alias ExRatatui.Style
      iex> Span.new("error", style: %Style{fg: :red, modifiers: [:bold]})
      %ExRatatui.Text.Span{
        content: "error",
        style: %ExRatatui.Style{fg: :red, bg: nil, modifiers: [:bold]}
      }

  Newlines in span content raise `ArgumentError` — split into multiple spans
  inside a `Line`, or multiple `Line`s inside a `Text`:

      iex> ExRatatui.Text.Span.new("a\\nb")
      ** (ArgumentError) Span content cannot contain newlines; use multiple Lines instead
  """

  alias ExRatatui.Style

  @type t :: %__MODULE__{
          content: String.t(),
          style: Style.t()
        }

  defstruct content: "", style: %Style{}

  @doc """
  Builds a `%Span{}` with the given content and options.

  Options:

    * `:style` - a `%ExRatatui.Style{}` (default: `%Style{}`)

  Raises `ArgumentError` if `content` contains `\\n`.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(content, opts \\ []) when is_binary(content) do
    if String.contains?(content, "\n") do
      raise ArgumentError,
            "Span content cannot contain newlines; use multiple Lines instead"
    end

    %__MODULE__{
      content: content,
      style: Keyword.get(opts, :style, %Style{})
    }
  end
end
