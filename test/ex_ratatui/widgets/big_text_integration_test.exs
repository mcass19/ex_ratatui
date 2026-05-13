defmodule ExRatatui.Widgets.BigTextIntegrationTest do
  @moduledoc """
  End-to-end checks for BigText: Elixir struct → Bridge encoding →
  NIF decode → ratatui render → cell buffer. Drives a `CellSession`
  rather than asserting against the byte buffer so we can inspect the
  exact glyph cells the widget painted.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{BigText, Popup, WidgetList}

  # Symbols ratatui-image-style block art and the font8x8 raster both
  # paint with. Any of these in a cell means BigText put a glyph there.
  @block_symbols ~w(▀ ▄ █ ▐ ▌)

  defp draw_cells(widget, %Rect{} = rect) do
    commands = Bridge.encode_commands!([{widget, rect}])
    ref = Native.cell_session_new(rect.width, rect.height)
    :ok = Native.cell_session_draw(ref, commands)
    %{cells: cells} = Native.cell_session_take_cells(ref)
    :ok = Native.cell_session_close(ref)
    cells
  end

  defp paints_glyph?(cells) do
    Enum.any?(cells, fn {_x, _y, symbol, _fg, _bg, _mods, _skip} ->
      symbol in @block_symbols
    end)
  end

  defp first_glyph_column(cells) do
    cells
    |> Enum.filter(fn {_x, _y, sym, _, _, _, _} -> sym in @block_symbols end)
    |> Enum.map(fn {x, _, _, _, _, _, _} -> x end)
    |> Enum.min(fn -> nil end)
  end

  describe "single-line rendering" do
    test "paints glyph cells through the full stack at :full pixel size" do
      widget = %BigText{
        lines: [%ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: "HI"}]}],
        pixel_size: :full
      }

      cells = draw_cells(widget, %Rect{x: 0, y: 0, width: 80, height: 16})
      assert paints_glyph?(cells), "expected at least one block-glyph cell"
    end

    test "smaller pixel sizes still paint glyphs into the cell grid" do
      for pixel_size <- [:half_height, :quadrant, :sextant, :octant] do
        widget = %BigText{
          lines: [%ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: "AB"}]}],
          pixel_size: pixel_size
        }

        cells = draw_cells(widget, %Rect{x: 0, y: 0, width: 40, height: 8})
        assert paints_glyph?(cells), "pixel_size #{inspect(pixel_size)} produced no glyphs"
      end
    end
  end

  describe "alignment" do
    test "centered text starts further right than left-aligned text" do
      rect = %Rect{x: 0, y: 0, width: 80, height: 16}

      left =
        draw_cells(
          %BigText{
            lines: [%ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: "A"}]}],
            pixel_size: :full,
            alignment: :left
          },
          rect
        )

      centered =
        draw_cells(
          %BigText{
            lines: [%ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: "A"}]}],
            pixel_size: :full,
            alignment: :center
          },
          rect
        )

      assert first_glyph_column(centered) > first_glyph_column(left)
    end
  end

  describe "styling" do
    test "fg color reaches the painted glyph cells" do
      widget = %BigText{
        lines: [%ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: "X"}]}],
        pixel_size: :full,
        style: %Style{fg: :red}
      }

      cells = draw_cells(widget, %Rect{x: 0, y: 0, width: 40, height: 16})

      reds =
        Enum.filter(cells, fn {_x, _y, sym, fg, _bg, _, _} ->
          sym in @block_symbols and fg == :red
        end)

      assert reds != [], "expected at least one painted cell with fg :red"
    end
  end

  describe "composed inside container widgets" do
    test "BigText nested in a Popup still paints glyphs" do
      inner = %BigText{
        lines: [%ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: "HI"}]}],
        pixel_size: :half_height
      }

      popup = %Popup{
        content: inner,
        percent_width: 100,
        percent_height: 100
      }

      cells = draw_cells(popup, %Rect{x: 0, y: 0, width: 40, height: 10})
      assert paints_glyph?(cells), "expected glyphs inside the Popup"
    end

    test "BigText nested in a WidgetList still paints glyphs" do
      inner = %BigText{
        lines: [%ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: "HI"}]}],
        pixel_size: :quadrant
      }

      list = %WidgetList{items: [{inner, 8}]}

      cells = draw_cells(list, %Rect{x: 0, y: 0, width: 40, height: 8})
      assert paints_glyph?(cells), "expected glyphs inside the WidgetList"
    end
  end
end
