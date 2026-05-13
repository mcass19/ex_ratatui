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
  alias ExRatatui.Widgets.{BigText, Block, Popup, WidgetList}

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

    test "per-Span style overrides the widget-level style" do
      # Widget-level style says :red; the only span requests :green.
      # The painted glyph cells should be green, not red — confirming
      # the ratatui text-styling cascade carries through our render
      # path (span beats widget on conflicts).
      widget = %BigText{
        lines: [
          %ExRatatui.Text.Line{
            spans: [%ExRatatui.Text.Span{content: "G", style: %Style{fg: :green}}]
          }
        ],
        pixel_size: :full,
        style: %Style{fg: :red}
      }

      cells = draw_cells(widget, %Rect{x: 0, y: 0, width: 40, height: 16})

      greens =
        Enum.filter(cells, fn {_x, _y, sym, fg, _bg, _, _} ->
          sym in @block_symbols and fg == :green
        end)

      reds_on_glyphs =
        Enum.filter(cells, fn {_x, _y, sym, fg, _bg, _, _} ->
          sym in @block_symbols and fg == :red
        end)

      assert greens != [], "expected per-span :green to win on at least one glyph"
      assert reds_on_glyphs == [], "no glyph cell should be widget-level :red"
    end
  end

  describe "block container (end-to-end)" do
    test "block borders paint alongside big-text glyphs" do
      # Confirm both the block's border and the BigText glyphs land in
      # the same render. End-to-end coverage for the
      # upstream-native-block-field path (no Elixir-side block layering).
      widget = %BigText{
        lines: [%ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: "X"}]}],
        pixel_size: :half_height,
        block: %Block{
          title: "title",
          borders: [:all],
          border_type: :rounded
        }
      }

      cells = draw_cells(widget, %Rect{x: 0, y: 0, width: 40, height: 10})

      # Corner cell should hold a rounded border glyph, not a space.
      corner_symbol =
        cells
        |> Enum.find(fn {x, y, _, _, _, _, _} -> x == 0 and y == 0 end)
        |> elem(2)

      assert corner_symbol in ~w(╭ ┌ ╔ ╓ ╒)

      # And the inner area still receives big-text glyphs.
      assert paints_glyph?(cells), "expected big-text glyphs alongside the border"

      # Title text from the block lands somewhere on row 0.
      row0_chars =
        cells
        |> Enum.filter(fn {_x, y, _, _, _, _, _} -> y == 0 end)
        |> Enum.map_join("", fn {_, _, sym, _, _, _, _} -> sym end)

      assert row0_chars =~ "title"
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
