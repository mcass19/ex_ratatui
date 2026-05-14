defmodule ExRatatui.CodeBlock do
  @moduledoc """
  Helpers for syntax-highlighted code, complementing the
  `ExRatatui.Widgets.CodeBlock` widget.

  `highlight/3` is the seam for users composing their own widgets — a
  DiffViewer building side-by-side panels of highlighted source, an
  Inspector pretty-printing structs — without dropping a full `CodeBlock`
  into the tree.

  ## Supported languages

  Powered by syntect's bundled Sublime-syntax set, plus **Elixir** which
  we ship in addition to the defaults (see
  `native/ex_ratatui/syntaxes/`). Languages with built-in support:
  Bash, C, C++, C#, CSS, D, Diff, **Elixir**, Erlang, Go, Groovy,
  Haskell, HTML, Java, JavaScript, JSON, Lisp, Lua, Make, Markdown,
  MATLAB, OCaml, Objective-C, Pascal, Perl, PHP, Python, R, Regexp, Ruby,
  Rust, Scala, Shell-Script, SQL, TCL, XML, YAML. Unknown languages fall
  back to plain text (still themed, but uncoloured).

  Lookup is case-insensitive and accepts file extensions, so `"elixir"`,
  `:Elixir`, `"ex"`, and `"exs"` all resolve to the same syntax.

  ## Themes

  Curated atoms resolve to syntect's bundled `ThemeSet`:

    * `:base16_ocean_dark` (default for `ExRatatui.Widgets.CodeBlock`)
    * `:base16_ocean_light`
    * `:base16_eighties_dark`
    * `:base16_mocha_dark`
    * `:inspired_github`
    * `:solarized_dark`
    * `:solarized_light`

  Raw strings pass through unchanged.

  ## Examples

      iex> [%ExRatatui.Text.Line{} | _] =
      ...>   ExRatatui.CodeBlock.highlight("fn main() {}", "rust", :base16_ocean_dark)
  """

  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.CodeBlock, as: CodeBlockWidget

  @code_themes %{
    base16_ocean_dark: "base16-ocean.dark",
    base16_ocean_light: "base16-ocean.light",
    base16_eighties_dark: "base16-eighties.dark",
    base16_mocha_dark: "base16-mocha.dark",
    inspired_github: "InspiredGitHub",
    solarized_dark: "Solarized (dark)",
    solarized_light: "Solarized (light)"
  }

  @doc """
  Resolves a `CodeBlock` theme into the raw syntect theme name.

  Accepts a curated atom (one of seven) or a raw string. Raises
  `ArgumentError` for unknown atoms with a message listing valid choices.
  Raw strings pass through unchanged so callers can load custom theme
  sets without modifying this module.
  """
  @spec resolve_theme(CodeBlockWidget.theme()) :: String.t()
  def resolve_theme(theme) when is_binary(theme), do: theme

  def resolve_theme(theme) when is_atom(theme) do
    case Map.fetch(@code_themes, theme) do
      {:ok, name} ->
        name

      :error ->
        valid =
          @code_themes
          |> Map.keys()
          |> Enum.sort()
          |> Enum.map_join(", ", &inspect/1)

        raise ArgumentError,
              "unknown CodeBlock theme #{inspect(theme)}, valid atoms: #{valid}"
    end
  end

  @doc """
  Highlight `code` for `language` using `theme`.

  Returns a list of `%ExRatatui.Text.Line{}` with per-token styled spans.
  Unknown languages fall back to a single plain span per line; unknown
  themes fall back to `:base16_ocean_dark`.

  ## Examples

      iex> [%ExRatatui.Text.Line{spans: spans} | _] =
      ...>   ExRatatui.CodeBlock.highlight("hello", nil, :base16_ocean_dark)
      iex> Enum.map(spans, & &1.content) |> Enum.join() |> String.trim()
      "hello"
  """
  @spec highlight(String.t(), String.t() | atom() | nil, CodeBlockWidget.theme()) :: [Line.t()]
  def highlight(code, language, theme) when is_binary(code) do
    theme_name = resolve_theme(theme)
    language_str = normalize_language(language)
    start_meta = %{language: language_str, theme: theme_name, bytes: byte_size(code)}

    :telemetry.span([:ex_ratatui, :code_block, :highlight], start_meta, fn ->
      lines =
        code
        |> Native.highlight_code(language_str, theme_name)
        |> from_native()

      {lines, Map.put(start_meta, :line_count, length(lines))}
    end)
  end

  defp normalize_language(nil), do: nil
  defp normalize_language(lang) when is_binary(lang), do: lang
  defp normalize_language(lang) when is_atom(lang), do: Atom.to_string(lang)

  @typedoc """
  Raw span shape returned by the underlying highlighter NIF.

  `fg`/`bg` are `nil` for the theme's default (when syntect's effective
  alpha is `0`), or a `{r, g, b}` tuple otherwise.
  """
  @type native_span :: %{
          content: String.t(),
          fg: nil | {0..255, 0..255, 0..255},
          bg: nil | {0..255, 0..255, 0..255},
          bold: boolean(),
          italic: boolean(),
          underlined: boolean()
        }

  @doc """
  Converts the raw NIF response into `%ExRatatui.Text.Line{}` structs.

  Useful for callers reaching for the underlying highlighter directly
  to skip per-call theme atom resolution (e.g. in a hot loop reusing the
  same theme), or for tooling that consumes the wire shape. Most callers
  should use `highlight/3` instead — it resolves the theme and emits the
  `[:ex_ratatui, :code_block, :highlight]` telemetry span.

  ## Examples

      iex> raw = [[%{content: "x", fg: {10, 20, 30}, bg: nil,
      ...>           bold: true, italic: false, underlined: false}]]
      iex> [%ExRatatui.Text.Line{spans: [span]}] = ExRatatui.CodeBlock.from_native(raw)
      iex> {span.content, span.style.fg, span.style.modifiers}
      {"x", {:rgb, 10, 20, 30}, [:bold]}
  """
  @spec from_native([[native_span()]]) :: [Line.t()]
  def from_native(lines) when is_list(lines), do: Enum.map(lines, &to_line/1)

  defp to_line(spans) when is_list(spans) do
    %Line{spans: Enum.map(spans, &to_span/1)}
  end

  defp to_span(%{
         content: content,
         fg: fg,
         bg: bg,
         bold: bold,
         italic: italic,
         underlined: underlined
       }) do
    %Span{
      content: content,
      style: %Style{
        fg: to_color(fg),
        bg: to_color(bg),
        modifiers: collect_modifiers(bold, italic, underlined)
      }
    }
  end

  defp to_color(nil), do: nil
  defp to_color({r, g, b}), do: {:rgb, r, g, b}

  defp collect_modifiers(bold, italic, underlined) do
    [{:bold, bold}, {:italic, italic}, {:underlined, underlined}]
    |> Enum.filter(fn {_, on?} -> on? end)
    |> Enum.map(fn {name, _} -> name end)
  end
end
