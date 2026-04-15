defmodule ExRatatui.TextTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.Text
  doctest ExRatatui.Text.Line
  doctest ExRatatui.Text.Span

  alias ExRatatui.Style
  alias ExRatatui.Text
  alias ExRatatui.Text.{Line, Span}

  describe "Span.new/2" do
    test "defaults style to empty Style" do
      assert Span.new("foo") == %Span{content: "foo", style: %Style{}}
    end

    test "accepts a style option" do
      style = %Style{fg: :red, modifiers: [:bold]}
      assert Span.new("foo", style: style) == %Span{content: "foo", style: style}
    end

    test "allows empty content" do
      assert Span.new("") == %Span{content: "", style: %Style{}}
    end

    test "raises on embedded newline" do
      assert_raise ArgumentError, ~r/cannot contain newlines/, fn ->
        Span.new("a\nb")
      end
    end

    test "raises on embedded newline even with trailing text" do
      assert_raise ArgumentError, ~r/cannot contain newlines/, fn ->
        Span.new("trailing\n")
      end
    end
  end

  describe "Line.new/2" do
    test "defaults style to empty Style and alignment to nil" do
      span = Span.new("hi")
      assert Line.new([span]) == %Line{spans: [span], style: %Style{}, alignment: nil}
    end

    test "accepts style and alignment options" do
      span = Span.new("hi")
      style = %Style{modifiers: [:italic]}
      line = Line.new([span], style: style, alignment: :center)
      assert line == %Line{spans: [span], style: style, alignment: :center}
    end

    test "accepts empty span list" do
      assert Line.new([]) == %Line{spans: [], style: %Style{}, alignment: nil}
    end

    test "accepts each valid alignment value" do
      for alignment <- [:left, :center, :right, nil] do
        assert %Line{alignment: ^alignment} = Line.new([], alignment: alignment)
      end
    end

    test "raises on invalid alignment" do
      assert_raise ArgumentError, ~r/invalid alignment/, fn ->
        Line.new([], alignment: :justify)
      end
    end
  end

  describe "Text.new/2" do
    test "defaults style to empty Style and alignment to nil" do
      line = Line.new([Span.new("hi")])
      assert Text.new([line]) == %Text{lines: [line], style: %Style{}, alignment: nil}
    end

    test "accepts style and alignment options" do
      line = Line.new([Span.new("hi")])
      style = %Style{fg: :blue}
      text = Text.new([line], style: style, alignment: :right)
      assert text == %Text{lines: [line], style: style, alignment: :right}
    end

    test "accepts empty line list" do
      assert Text.new([]) == %Text{lines: [], style: %Style{}, alignment: nil}
    end

    test "accepts each valid alignment value" do
      for alignment <- [:left, :center, :right, nil] do
        assert %Text{alignment: ^alignment} = Text.new([], alignment: alignment)
      end
    end

    test "raises on invalid alignment" do
      assert_raise ArgumentError, ~r/invalid alignment/, fn ->
        Text.new([], alignment: :top)
      end
    end
  end
end
