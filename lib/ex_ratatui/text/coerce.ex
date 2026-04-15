defmodule ExRatatui.Text.Coerce do
  @moduledoc false

  alias ExRatatui.Text
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span

  @doc """
  Normalizes any accepted text-like shape into a canonical `%Text{}`.

  Accepted shapes:

    * `String.t()` — split on `"\\n"` into one line per chunk
    * `%Span{}` — wrapped into a single line
    * `%Line{}` — wrapped in a `%Text{}`
    * `%Text{}` — returned as-is
    * `[%Span{}]` — becomes one line
    * `[%Line{}]` — becomes the text's lines
    * `[]` — empty text (no lines)

  Raises `ArgumentError` on any other shape or on a mixed list.
  """
  @spec coerce_text!(term()) :: Text.t()
  def coerce_text!(value)

  def coerce_text!(%Text{} = text), do: text
  def coerce_text!(%Line{} = line), do: %Text{lines: [line]}
  def coerce_text!(%Span{} = span), do: %Text{lines: [%Line{spans: [span]}]}

  def coerce_text!(value) when is_binary(value) do
    lines =
      value
      |> String.split("\n")
      |> Enum.map(fn chunk -> %Line{spans: [%Span{content: chunk}]} end)

    %Text{lines: lines}
  end

  def coerce_text!([]), do: %Text{lines: []}

  def coerce_text!([%Line{} | _] = lines) do
    ensure_all!(lines, Line, "%Line{}")
    %Text{lines: lines}
  end

  def coerce_text!([%Span{} | _] = spans) do
    ensure_all!(spans, Span, "%Span{}")
    %Text{lines: [%Line{spans: spans}]}
  end

  def coerce_text!(other) do
    raise ArgumentError, "cannot coerce #{inspect(other)} into %ExRatatui.Text{}"
  end

  @doc """
  Normalizes any accepted line-like shape into a canonical `%Line{}`.

  Accepted shapes:

    * `String.t()` — wraps into one span; embedded `"\\n"` raises
    * `%Span{}` — wrapped into a single-span line
    * `%Line{}` — returned as-is
    * `[%Span{}]` — becomes the line's spans
    * `[]` — empty line (no spans)

  Raises `ArgumentError` on any other shape or on a mixed list.
  """
  @spec coerce_line!(term()) :: Line.t()
  def coerce_line!(value)

  def coerce_line!(%Line{} = line), do: line
  def coerce_line!(%Span{} = span), do: %Line{spans: [span]}

  def coerce_line!(value) when is_binary(value) do
    if String.contains?(value, "\n") do
      raise ArgumentError,
            "expected single-line input, got string with newline: #{inspect(value)}"
    end

    %Line{spans: [%Span{content: value}]}
  end

  def coerce_line!([]), do: %Line{spans: []}

  def coerce_line!([%Span{} | _] = spans) do
    ensure_all!(spans, Span, "%Span{}")
    %Line{spans: spans}
  end

  def coerce_line!(other) do
    raise ArgumentError, "cannot coerce #{inspect(other)} into %ExRatatui.Text.Line{}"
  end

  defp ensure_all!(list, module, label) do
    if Enum.all?(list, &match_struct?(&1, module)) do
      :ok
    else
      raise ArgumentError, "expected a list of #{label}, got mixed list: #{inspect(list)}"
    end
  end

  defp match_struct?(%mod{}, mod), do: true
  defp match_struct?(_, _), do: false
end
