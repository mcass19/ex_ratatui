defmodule ExRatatui.Text.Encode do
  @moduledoc false

  alias ExRatatui.Style
  alias ExRatatui.Text
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span

  @doc """
  Converts a canonical `%Text{}` into the NIF wire map.
  """
  @spec to_wire_text!(Text.t()) :: map()
  def to_wire_text!(%Text{} = text) do
    %{
      "lines" => Enum.map(text.lines, &encode_line/1),
      "style" => encode_style!(text.style)
    }
    |> maybe_put("alignment", encode_alignment(text.alignment))
  end

  @doc """
  Converts a canonical `%Line{}` into the NIF wire map.
  """
  @spec to_wire_line!(Line.t()) :: map()
  def to_wire_line!(%Line{} = line), do: encode_line(line)

  defp encode_line(%Line{} = line) do
    %{
      "spans" => Enum.map(line.spans, &encode_span/1),
      "style" => encode_style!(line.style)
    }
    |> maybe_put("alignment", encode_alignment(line.alignment))
  end

  defp encode_span(%Span{} = span) do
    %{
      "content" => span.content,
      "style" => encode_style!(span.style)
    }
  end

  defp encode_alignment(nil), do: nil
  defp encode_alignment(align) when align in [:left, :center, :right], do: Atom.to_string(align)

  defp encode_style!(%Style{} = style) do
    %{"modifiers" => Enum.map(style.modifiers, &Atom.to_string/1)}
    |> maybe_put("fg", encode_color(style.fg))
    |> maybe_put("bg", encode_color(style.bg))
  end

  defp encode_color(nil), do: nil
  defp encode_color(color) when is_atom(color), do: Atom.to_string(color)
  defp encode_color({:rgb, r, g, b}), do: %{"type" => "rgb", "r" => r, "g" => g, "b" => b}
  defp encode_color({:indexed, index}), do: %{"type" => "indexed", "value" => index}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
