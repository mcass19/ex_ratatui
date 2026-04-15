defmodule ExRatatui.Text.CoerceTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Text
  alias ExRatatui.Text.Coerce
  alias ExRatatui.Text.{Line, Span}

  describe "coerce_text!/1" do
    test "returns %Text{} unchanged" do
      text = Text.new([Line.new([Span.new("hi")])])
      assert Coerce.coerce_text!(text) == text
    end

    test "wraps a %Line{} into a %Text{}" do
      line = Line.new([Span.new("hi")])
      assert Coerce.coerce_text!(line) == %Text{lines: [line]}
    end

    test "wraps a %Span{} into a single-span single-line %Text{}" do
      span = Span.new("hi")
      assert Coerce.coerce_text!(span) == %Text{lines: [%Line{spans: [span]}]}
    end

    test "splits a plain string on newlines" do
      assert Coerce.coerce_text!("a\nb") == %Text{
               lines: [
                 %Line{spans: [%Span{content: "a"}]},
                 %Line{spans: [%Span{content: "b"}]}
               ]
             }
    end

    test "handles empty string as a single empty-content line" do
      assert Coerce.coerce_text!("") == %Text{lines: [%Line{spans: [%Span{content: ""}]}]}
    end

    test "handles single-line string without newlines" do
      assert Coerce.coerce_text!("hello") == %Text{
               lines: [%Line{spans: [%Span{content: "hello"}]}]
             }
    end

    test "handles trailing newline as a trailing empty line" do
      assert Coerce.coerce_text!("foo\n") == %Text{
               lines: [
                 %Line{spans: [%Span{content: "foo"}]},
                 %Line{spans: [%Span{content: ""}]}
               ]
             }
    end

    test "empty list becomes an empty %Text{}" do
      assert Coerce.coerce_text!([]) == %Text{lines: []}
    end

    test "list of %Line{} becomes the text's lines" do
      line1 = Line.new([Span.new("a")])
      line2 = Line.new([Span.new("b")])
      assert Coerce.coerce_text!([line1, line2]) == %Text{lines: [line1, line2]}
    end

    test "list of %Span{} becomes a single line" do
      s1 = Span.new("a")
      s2 = Span.new("b")
      assert Coerce.coerce_text!([s1, s2]) == %Text{lines: [%Line{spans: [s1, s2]}]}
    end

    test "raises on mixed list of %Line{} and %Span{}" do
      assert_raise ArgumentError, ~r/mixed list/, fn ->
        Coerce.coerce_text!([Line.new([]), Span.new("x")])
      end
    end

    test "raises on mixed list of %Span{} and other" do
      assert_raise ArgumentError, ~r/mixed list/, fn ->
        Coerce.coerce_text!([Span.new("x"), :not_a_span])
      end
    end

    test "raises on unsupported shape" do
      assert_raise ArgumentError, ~r/cannot coerce/, fn ->
        Coerce.coerce_text!(:atom)
      end
    end

    test "raises on list with unsupported head element" do
      assert_raise ArgumentError, ~r/cannot coerce/, fn ->
        Coerce.coerce_text!([:not_a_span_or_line])
      end
    end
  end

  describe "coerce_line!/1" do
    test "returns %Line{} unchanged" do
      line = Line.new([Span.new("hi")])
      assert Coerce.coerce_line!(line) == line
    end

    test "wraps a %Span{} into a single-span %Line{}" do
      span = Span.new("hi")
      assert Coerce.coerce_line!(span) == %Line{spans: [span]}
    end

    test "wraps a plain string into a single-span line" do
      assert Coerce.coerce_line!("hello") == %Line{spans: [%Span{content: "hello"}]}
    end

    test "empty string becomes a single empty-content span line" do
      assert Coerce.coerce_line!("") == %Line{spans: [%Span{content: ""}]}
    end

    test "raises on string with embedded newline" do
      assert_raise ArgumentError, ~r/single-line/, fn ->
        Coerce.coerce_line!("a\nb")
      end
    end

    test "empty list becomes an empty-spans %Line{}" do
      assert Coerce.coerce_line!([]) == %Line{spans: []}
    end

    test "list of %Span{} becomes the line's spans" do
      s1 = Span.new("a")
      s2 = Span.new("b")
      assert Coerce.coerce_line!([s1, s2]) == %Line{spans: [s1, s2]}
    end

    test "raises on mixed list" do
      assert_raise ArgumentError, ~r/mixed list/, fn ->
        Coerce.coerce_line!([Span.new("a"), :atom])
      end
    end

    test "raises on unsupported shape" do
      assert_raise ArgumentError, ~r/cannot coerce/, fn ->
        Coerce.coerce_line!(123)
      end
    end

    test "raises on list with unsupported head element" do
      assert_raise ArgumentError, ~r/cannot coerce/, fn ->
        Coerce.coerce_line!([:not_a_span])
      end
    end
  end
end
