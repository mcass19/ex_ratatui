defmodule ExRatatui.BigTextTest do
  use ExUnit.Case, async: true

  alias ExRatatui.BigText
  alias ExRatatui.Style
  alias ExRatatui.Text
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.BigText, as: Widget

  describe "new/2 coercion" do
    test "coerces a binary into a single line" do
      assert %Widget{lines: [%Line{spans: [%Span{content: "HELLO"}]}]} =
               BigText.new("HELLO")
    end

    test "splits a multi-line binary on newlines" do
      assert %Widget{lines: lines} = BigText.new("ONE\nTWO\nTHREE")
      assert length(lines) == 3
      assert [%Line{spans: [%Span{content: "ONE"}]} | _] = lines
    end

    test "accepts a single %Line{}" do
      line = %Line{spans: [%Span{content: "x"}]}
      assert %Widget{lines: [^line]} = BigText.new(line)
    end

    test "accepts a single %Span{}" do
      span = %Span{content: "x"}
      assert %Widget{lines: [%Line{spans: [^span]}]} = BigText.new(span)
    end

    test "accepts a full %Text{} and merges outer style + alignment" do
      text = %Text{
        lines: [%Line{spans: [%Span{content: "A"}]}],
        style: %Style{fg: :red},
        alignment: :center
      }

      widget = BigText.new(text)
      assert widget.alignment == :center
      assert widget.style.fg == :red
    end

    test "accepts a list of %Line{}" do
      lines = [
        %Line{spans: [%Span{content: "a"}]},
        %Line{spans: [%Span{content: "b"}]}
      ]

      assert %Widget{lines: ^lines} = BigText.new(lines)
    end

    test "accepts a list of %Span{}" do
      spans = [%Span{content: "a"}, %Span{content: "b"}]
      assert %Widget{lines: [%Line{spans: ^spans}]} = BigText.new(spans)
    end
  end

  describe "new/2 options" do
    test "defaults match the struct defaults" do
      widget = BigText.new("X")
      assert widget.pixel_size == :full
      assert widget.alignment == :left
      assert widget.style == %Style{}
      assert widget.block == nil
    end

    test "honors :pixel_size, :alignment, :style" do
      widget =
        BigText.new("HI",
          pixel_size: :quadrant,
          alignment: :center,
          style: %Style{fg: :magenta}
        )

      assert widget.pixel_size == :quadrant
      assert widget.alignment == :center
      assert widget.style.fg == :magenta
    end

    test "widget-level :style overrides %Text{} :style on the same field" do
      text = %Text{
        lines: [%Line{spans: [%Span{content: "A"}]}],
        style: %Style{fg: :red, bg: :blue}
      }

      # :fg is overridden, :bg falls through from the text
      widget = BigText.new(text, style: %Style{fg: :green})
      assert widget.style.fg == :green
      assert widget.style.bg == :blue
    end

    test ":alignment opt wins over %Text{} alignment" do
      text = %Text{
        lines: [%Line{spans: [%Span{content: "A"}]}],
        alignment: :center
      }

      widget = BigText.new(text, alignment: :right)
      assert widget.alignment == :right
    end

    test "accepts a :block option verbatim" do
      block = %ExRatatui.Widgets.Block{title: "hello"}
      widget = BigText.new("X", block: block)
      assert widget.block == block
    end

    test "rejects an unknown :pixel_size atom" do
      assert_raise ArgumentError, ~r/expected :pixel_size to be one of/, fn ->
        BigText.new("X", pixel_size: :massive)
      end
    end

    test "rejects an unknown :alignment atom" do
      assert_raise ArgumentError, ~r/expected :alignment to be one of/, fn ->
        BigText.new("X", alignment: :nowhere)
      end
    end

    test "rejects a non-%Style{} :style value" do
      assert_raise ArgumentError, ~r/expected :style to be a %ExRatatui.Style{}/, fn ->
        BigText.new("X", style: "blue")
      end
    end
  end

  describe "bridge encoding" do
    test "the widget round-trips through the render pipeline" do
      # Smoke test that ExRatatui.draw/2 accepts the struct shape the
      # public constructor produces — covers the bridge encoder.
      terminal = ExRatatui.init_test_terminal(40, 10)

      try do
        widget = BigText.new("HI", pixel_size: :half_height, alignment: :center)
        rect = %ExRatatui.Layout.Rect{x: 0, y: 0, width: 40, height: 8}
        assert :ok = ExRatatui.draw(terminal, [{widget, rect}])
        content = ExRatatui.get_buffer_content(terminal)
        # half_height uses ▀ / ▄ blocks for the pixel grid.
        assert content =~ ~r/[▀▄█]/
      after
        ExRatatui.Native.restore_terminal(terminal)
      end
    end
  end
end
