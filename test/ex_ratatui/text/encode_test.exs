defmodule ExRatatui.Text.EncodeTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Style
  alias ExRatatui.Text
  alias ExRatatui.Text.Encode
  alias ExRatatui.Text.{Line, Span}

  describe "to_wire_text!/1" do
    test "encodes an empty %Text{} to lines=[], omitted alignment, no fg/bg" do
      assert Encode.to_wire_text!(%Text{}) == %{
               "lines" => [],
               "style" => %{"modifiers" => []}
             }
    end

    test "encodes a single-line %Text{} with no styling" do
      text = Text.new([Line.new([Span.new("hi")])])

      assert Encode.to_wire_text!(text) == %{
               "lines" => [
                 %{
                   "spans" => [
                     %{"content" => "hi", "style" => %{"modifiers" => []}}
                   ],
                   "style" => %{"modifiers" => []}
                 }
               ],
               "style" => %{"modifiers" => []}
             }
    end

    test "encodes all style fields (fg, bg, modifiers, alignment)" do
      text =
        Text.new(
          [
            Line.new(
              [Span.new("hi", style: %Style{fg: :red, modifiers: [:bold]})],
              style: %Style{bg: :blue},
              alignment: :center
            )
          ],
          style: %Style{fg: :green, modifiers: [:italic]},
          alignment: :right
        )

      assert Encode.to_wire_text!(text) == %{
               "lines" => [
                 %{
                   "spans" => [
                     %{
                       "content" => "hi",
                       "style" => %{
                         "modifiers" => ["bold"],
                         "fg" => "red"
                       }
                     }
                   ],
                   "style" => %{"modifiers" => [], "bg" => "blue"},
                   "alignment" => "center"
                 }
               ],
               "style" => %{"modifiers" => ["italic"], "fg" => "green"},
               "alignment" => "right"
             }
    end

    test "encodes rgb color" do
      text = Text.new([Line.new([Span.new("hi", style: %Style{fg: {:rgb, 10, 20, 30}})])])
      wire = Encode.to_wire_text!(text)
      [%{"spans" => [span]}] = wire["lines"]
      assert span["style"]["fg"] == %{"type" => "rgb", "r" => 10, "g" => 20, "b" => 30}
    end

    test "encodes indexed color" do
      text = Text.new([Line.new([Span.new("hi", style: %Style{bg: {:indexed, 42}})])])
      wire = Encode.to_wire_text!(text)
      [%{"spans" => [span]}] = wire["lines"]
      assert span["style"]["bg"] == %{"type" => "indexed", "value" => 42}
    end

    test "encodes :left alignment" do
      text = Text.new([], alignment: :left)
      assert Encode.to_wire_text!(text)["alignment"] == "left"
    end

    test "omits alignment key when nil" do
      assert Encode.to_wire_text!(%Text{}) |> Map.has_key?("alignment") == false
    end
  end

  describe "to_wire_line!/1" do
    test "encodes an empty %Line{}" do
      assert Encode.to_wire_line!(%Line{}) == %{
               "spans" => [],
               "style" => %{"modifiers" => []}
             }
    end

    test "encodes a styled line with spans" do
      line =
        Line.new(
          [
            Span.new("ok", style: %Style{fg: :green}),
            Span.new(" ", style: %Style{}),
            Span.new("done", style: %Style{modifiers: [:bold]})
          ],
          style: %Style{bg: :black},
          alignment: :left
        )

      assert Encode.to_wire_line!(line) == %{
               "spans" => [
                 %{"content" => "ok", "style" => %{"modifiers" => [], "fg" => "green"}},
                 %{"content" => " ", "style" => %{"modifiers" => []}},
                 %{"content" => "done", "style" => %{"modifiers" => ["bold"]}}
               ],
               "style" => %{"modifiers" => [], "bg" => "black"},
               "alignment" => "left"
             }
    end
  end
end
