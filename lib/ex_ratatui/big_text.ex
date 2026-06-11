defmodule ExRatatui.BigText do
  @moduledoc """
  Build oversized 8×8-pixel text widgets for slide titles and banners.

  Powered by [tui-big-text](https://github.com/ratatui/tui-widgets/tree/main/tui-big-text).
  Each character is rasterised through a bitmap font; the `pixel_size`
  option controls how many cells a single 8×8 pixel maps to.

  ```elixir
  banner = ExRatatui.BigText.new("HELLO", pixel_size: :quadrant, alignment: :center)

  def view(_model, frame) do
    area = %ExRatatui.Layout.Rect{x: 0, y: 0, width: frame.width, height: 10}
    [{banner, area}]
  end
  ```

  ## Options

    * `:pixel_size` - one of `:full` (default, one character cell per
      pixel), `:half_height`, `:half_width`, `:quadrant`, `:third_height`,
      `:sextant`, `:quarter_height`, `:octant`. Smaller variants pack
      more characters into the same area at the cost of legibility.
    * `:alignment` - `:left` (default), `:center`, or `:right`.
    * `:style` - `%ExRatatui.Style{}` applied to all rendered glyphs.
      Per-line and per-span styles in the input still win on conflict.
    * `:block` - optional `%ExRatatui.Widgets.Block{}` for a border /
      title around the big text.

  ## Accepted input shapes

  `new/2` coerces its first argument through the same path
  `ExRatatui.Paragraph` uses, so any text-like shape is accepted:

    * `String.t()` — split on `"\\n"` into one line per chunk
    * `%ExRatatui.Text.Line{}` or `%ExRatatui.Text.Span{}`
    * `%ExRatatui.Text{}` — the lines + outer style are unpacked
    * `[%Line{} | %Span{} | binary]` — list of any single accepted shape

  ## Sizing tip

  A `:full` glyph is 8×8 character cells. A two-character word at
  `:full` therefore needs ~16 cells wide and 8 cells tall. When
  targeting an 80×24 terminal, `:half_height` (4 rows tall) or
  `:quadrant` (4 rows tall, 4 cols wide) usually fits a 2–3 word title.
  """

  alias ExRatatui.Text
  alias ExRatatui.Text.Coerce
  alias ExRatatui.Widgets.BigText, as: Widget

  @type new_opts :: [
          pixel_size: Widget.pixel_size(),
          alignment: Widget.alignment(),
          style: ExRatatui.Style.t(),
          block: ExRatatui.Widgets.Block.t() | nil
        ]

  @valid_pixel_sizes ~w(full half_height half_width quadrant third_height sextant quarter_height octant)a
  @valid_alignments ~w(left center right)a

  @doc """
  Build a `%ExRatatui.Widgets.BigText{}` from text-like input.

  `text` accepts the same shapes any text-bearing widget accepts:
  a binary, a single `%Line{}` / `%Span{}`, a full `%Text{}`, or a
  homogeneous list. When a `%Text{}` is supplied (or coerced into),
  its outer `:style` is merged with the widget's own `:style` and its
  `:alignment` is preferred over the widget's default when set.

  Returns the widget struct directly; constructing fails fast with
  `ArgumentError` on a bad shape or invalid option (matching the rest
  of the widget surface — no `{:ok, _}` wrapper, no NIF call).

  ## Examples

      iex> ExRatatui.BigText.new("HELLO")
      %ExRatatui.Widgets.BigText{
        lines: [
          %ExRatatui.Text.Line{
            spans: [%ExRatatui.Text.Span{content: "HELLO", style: %ExRatatui.Style{}}],
            style: %ExRatatui.Style{},
            alignment: nil
          }
        ],
        pixel_size: :full,
        alignment: :left,
        style: %ExRatatui.Style{},
        block: nil
      }

      iex> widget = ExRatatui.BigText.new("HI", pixel_size: :quadrant, alignment: :center)
      iex> {widget.pixel_size, widget.alignment}
      {:quadrant, :center}

      iex> ExRatatui.BigText.new("X", pixel_size: :huge)
      ** (ArgumentError) expected :pixel_size to be one of [:full, :half_height, :half_width, :quadrant, :third_height, :sextant, :quarter_height, :octant], got: :huge
  """
  @spec new(term(), new_opts()) :: Widget.t()
  def new(text, opts \\ []) when is_list(opts) do
    %Text{lines: lines, style: text_style, alignment: text_alignment} = Coerce.coerce_text!(text)

    pixel_size = validate_pixel_size(Keyword.get(opts, :pixel_size, :full))
    alignment = validate_alignment(Keyword.get(opts, :alignment, text_alignment || :left))
    style = merge_style(text_style, Keyword.get(opts, :style, %ExRatatui.Style{}))
    block = Keyword.get(opts, :block)

    %Widget{
      lines: lines,
      pixel_size: pixel_size,
      alignment: alignment,
      style: style,
      block: block
    }
  end

  defp validate_pixel_size(value) when value in @valid_pixel_sizes, do: value

  defp validate_pixel_size(other) do
    raise ArgumentError,
          "expected :pixel_size to be one of #{inspect(@valid_pixel_sizes)}, got: #{inspect(other)}"
  end

  defp validate_alignment(value) when value in @valid_alignments, do: value

  defp validate_alignment(other) do
    raise ArgumentError,
          "expected :alignment to be one of #{inspect(@valid_alignments)}, got: #{inspect(other)}"
  end

  # The widget-level :style wins over the Text-level :style when both
  # define the same field — that's the "options layer overrides the
  # input layer" expectation for any widget constructor.
  defp merge_style(%ExRatatui.Style{} = text_style, %ExRatatui.Style{} = opt_style) do
    %ExRatatui.Style{
      fg: opt_style.fg || text_style.fg,
      bg: opt_style.bg || text_style.bg,
      modifiers: opt_style.modifiers ++ text_style.modifiers
    }
  end

  defp merge_style(_text_style, other) do
    raise ArgumentError,
          "expected :style to be a %ExRatatui.Style{}, got: #{inspect(other)}"
  end
end
