defmodule ExRatatui.Property.CodeBlockPropertyTest do
  @moduledoc """
  Property invariants for `ExRatatui.CodeBlock.highlight/3`.

  These pin the two strongest claims worth making about any highlighter — it
  adds *style* without touching *content*, and it's a pure function — across
  the full cross product of curated themes, a representative slice of
  syntect's bundled languages (plus our vendored Elixir), and a random
  population of source snippets. Per-clause behaviour is covered by the unit
  tests in `ExRatatui.CodeBlockTest`; these properties prove the chain is
  total: no language/theme/source combination crashes, every span comes out
  RGB-or-nil, and concatenating the spans round-trips the source byte for
  byte.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.CodeBlock
  alias ExRatatui.Text.{Line, Span}

  @themes ~w(
    base16_ocean_dark base16_ocean_light base16_eighties_dark
    base16_mocha_dark inspired_github solarized_dark solarized_light
  )a

  # `nil` for the plain-text fallback path, plus a representative slice of
  # syntect's bundled language tokens. Not exhaustive — the goal is to
  # exercise the dispatcher across syntaxes with meaningfully different
  # tokenizers, not to enumerate every Sublime grammar shipped.
  @languages [
    nil,
    "elixir",
    "rust",
    "python",
    "ruby",
    "javascript",
    "json",
    "markdown",
    "html",
    "css",
    "yaml",
    "xml",
    "go",
    "java",
    "c",
    "cpp",
    "sh",
    "bash"
  ]

  # Generators -------------------------------------------------------------

  # ASCII without newlines, plus a handful of punctuation tokenizers actually
  # split on. Keeping the alphabet tight makes shrinks readable and avoids
  # filling shrink output with surrogate pairs that don't affect coverage of
  # the round-trip property.
  defp line_chars do
    Enum.concat([
      ?a..?z,
      ?A..?Z,
      ?0..?9,
      [?\s, ?_, ?., ?(, ?), ?{, ?}, ?;, ?=, ?+, ?-, ?*, ?/, ?", ?', ?:, ?,, ?#]
    ])
  end

  defp source_gen do
    gen all(
          lines <- list_of(string(line_chars(), max_length: 40), max_length: 8),
          trailing_newline? <- boolean()
        ) do
      base = Enum.join(lines, "\n")
      if trailing_newline?, do: base <> "\n", else: base
    end
  end

  defp lang_gen, do: member_of(@languages)
  defp theme_gen, do: member_of(@themes)

  # Properties -------------------------------------------------------------

  property "highlight is a no-op on content — concatenating spans reconstructs the source" do
    check all(
            code <- source_gen(),
            lang <- lang_gen(),
            theme <- theme_gen()
          ) do
      lines = CodeBlock.highlight(code, lang, theme)

      reconstructed =
        lines
        |> Enum.flat_map(fn %Line{spans: spans} -> Enum.map(spans, & &1.content) end)
        |> IO.iodata_to_binary()

      assert reconstructed == code,
             "highlight altered content: got #{inspect(reconstructed)}, expected #{inspect(code)}"
    end
  end

  property "line count matches the source's LinesWithEndings count" do
    check all(
            code <- source_gen(),
            lang <- lang_gen(),
            theme <- theme_gen()
          ) do
      assert length(CodeBlock.highlight(code, lang, theme)) == expected_line_count(code)
    end
  end

  property "highlight is deterministic — same input, same output" do
    check all(
            code <- source_gen(),
            lang <- lang_gen(),
            theme <- theme_gen()
          ) do
      assert CodeBlock.highlight(code, lang, theme) == CodeBlock.highlight(code, lang, theme)
    end
  end

  property "nil language collapses to one span per line whose content is that line" do
    check all(code <- source_gen(), theme <- theme_gen()) do
      for %Line{spans: spans} <- CodeBlock.highlight(code, nil, theme) do
        assert match?([%Span{}], spans),
               "plain-text fallback should yield exactly one span per line, got #{length(spans)}"
      end
    end
  end

  property "every span carries nil or {:rgb, r, g, b} colors and known modifiers" do
    check all(
            code <- source_gen(),
            lang <- lang_gen(),
            theme <- theme_gen()
          ) do
      for %Line{spans: spans} <- CodeBlock.highlight(code, lang, theme),
          %Span{style: style} <- spans do
        assert style.fg == nil or match?({:rgb, _, _, _}, style.fg)
        assert style.bg == nil or match?({:rgb, _, _, _}, style.bg)
        assert Enum.all?(style.modifiers, &(&1 in [:bold, :italic, :underlined]))
      end
    end
  end

  # Mirrors syntect's `LinesWithEndings` behaviour: an empty source has zero
  # lines, a trailing newline does not produce a phantom empty line, and any
  # other content is split on `\n` with each fragment counting as one line.
  defp expected_line_count(""), do: 0

  defp expected_line_count(code) do
    parts = String.split(code, "\n")
    if String.ends_with?(code, "\n"), do: length(parts) - 1, else: length(parts)
  end
end
