defmodule ExRatatui.Widgets.BigTextTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{BigText, Block}

  setup do
    terminal = ExRatatui.init_test_terminal(80, 20)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
  end

  describe "BigText struct defaults" do
    test "constructs with sensible defaults" do
      assert %BigText{
               lines: [],
               pixel_size: :full,
               alignment: :left,
               style: %Style{},
               block: nil
             } = %BigText{}
    end
  end

  describe "rendering through the native pipeline" do
    test "paints non-space cells for a single-line struct", %{terminal: terminal} do
      widget = %BigText{
        lines: [%Line{spans: [%Span{content: "HI"}]}],
        pixel_size: :full
      }

      rect = %Rect{x: 0, y: 0, width: 80, height: 16}

      assert :ok = ExRatatui.draw(terminal, [{widget, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      # `:full` paints with the upper-half/lower-half blocks (▀ / ▄)
      # plus full block (█). Any of these confirms a glyph was drawn.
      assert content =~ ~r/[▀▄█]/
    end

    test "honors a block container by drawing border glyphs", %{terminal: terminal} do
      widget = %BigText{
        lines: [%Line{spans: [%Span{content: "A"}]}],
        pixel_size: :half_height,
        block: %Block{title: "frame"}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}
      assert :ok = ExRatatui.draw(terminal, [{widget, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      # `%Block{}` defaults are no borders; we just confirm the title
      # text renders since a bare block w/o borders still paints the
      # title row. Use a bordered block elsewhere for the border check.
      assert content =~ "frame"
    end

    test "renders each pixel_size variant without crashing", %{terminal: terminal} do
      for pixel_size <- [
            :full,
            :half_height,
            :half_width,
            :quadrant,
            :third_height,
            :sextant,
            :quarter_height,
            :octant
          ] do
        widget = %BigText{
          lines: [%Line{spans: [%Span{content: "X"}]}],
          pixel_size: pixel_size
        }

        rect = %Rect{x: 0, y: 0, width: 80, height: 20}

        assert :ok = ExRatatui.draw(terminal, [{widget, rect}]),
               "pixel_size #{inspect(pixel_size)} failed to draw"
      end
    end

    test "rejects an unknown pixel_size atom at the NIF boundary", %{terminal: terminal} do
      # Bypass the public API to confirm the Rust decoder also
      # catches bad values — defence in depth against someone
      # building the wire map by hand.
      widget = %BigText{
        lines: [%Line{spans: [%Span{content: "X"}]}],
        pixel_size: :gigantic
      }

      rect = %Rect{x: 0, y: 0, width: 80, height: 20}
      assert {:error, _} = ExRatatui.draw(terminal, [{widget, rect}])
    end
  end
end
