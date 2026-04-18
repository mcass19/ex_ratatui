defmodule ExRatatui.Widget.ExpanderTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widget.Expander
  alias ExRatatui.Widgets.{Block, Paragraph}

  defmodule Leaf do
    defstruct [:text]

    defimpl ExRatatui.Widget do
      def render(%{text: text}, rect) do
        [{%ExRatatui.Widgets.Paragraph{text: text}, rect}]
      end
    end
  end

  defmodule Pair do
    defstruct [:top, :bottom]

    defimpl ExRatatui.Widget do
      alias ExRatatui.Layout

      def render(%{top: top, bottom: bottom}, rect) do
        [top_rect, bottom_rect] =
          Layout.split(rect, :vertical, [{:percentage, 50}, {:percentage, 50}])

        [{top, top_rect}, {bottom, bottom_rect}]
      end
    end
  end

  defmodule Empty do
    defstruct []

    defimpl ExRatatui.Widget do
      def render(_, _rect), do: []
    end
  end

  defmodule SelfRecursive do
    defstruct []

    defimpl ExRatatui.Widget do
      def render(widget, rect), do: [{widget, rect}]
    end
  end

  defmodule BadNotList do
    defstruct []

    defimpl ExRatatui.Widget do
      def render(_, _), do: :nope
    end
  end

  defmodule BadEntry do
    defstruct []

    defimpl ExRatatui.Widget do
      def render(_, _rect), do: [:not_a_tuple]
    end
  end

  defmodule BadRect do
    defstruct []

    defimpl ExRatatui.Widget do
      def render(_, _rect), do: [{%ExRatatui.Widgets.Paragraph{text: "hi"}, {0, 0, 5, 1}}]
    end
  end

  @rect %Rect{x: 0, y: 0, width: 10, height: 4}

  describe "expand!/1" do
    test "returns an empty list unchanged" do
      assert Expander.expand!([]) == []
    end

    test "passes primitive widgets through unchanged" do
      commands = [{%Paragraph{text: "a"}, @rect}, {%Block{title: "b"}, @rect}]
      assert Expander.expand!(commands) == commands
    end

    test "expands a single custom widget into its children" do
      assert [{%Paragraph{text: "hi"}, @rect}] =
               Expander.expand!([{%Leaf{text: "hi"}, @rect}])
    end

    test "recursively expands custom widgets returning other custom widgets" do
      tree = %Pair{
        top: %Leaf{text: "top"},
        bottom: %Pair{top: %Leaf{text: "mid"}, bottom: %Leaf{text: "bot"}}
      }

      result = Expander.expand!([{tree, @rect}])

      texts = Enum.map(result, fn {%Paragraph{text: t}, _} -> t end)
      assert texts == ["top", "mid", "bot"]

      assert Enum.all?(result, fn {_widget, rect} -> match?(%Rect{}, rect) end)
    end

    test "custom widget returning an empty list expands to []" do
      assert Expander.expand!([{%Empty{}, @rect}]) == []
    end

    test "preserves z-order across nested expansion" do
      commands = [
        {%Paragraph{text: "first"}, @rect},
        {%Leaf{text: "middle"}, @rect},
        {%Paragraph{text: "last"}, @rect}
      ]

      texts =
        commands
        |> Expander.expand!()
        |> Enum.map(fn {%Paragraph{text: t}, _} -> t end)

      assert texts == ["first", "middle", "last"]
    end

    test "raises when depth cap is exceeded" do
      assert_raise ArgumentError,
                   ~r/exceeded max depth \(32\).*SelfRecursive/,
                   fn ->
                     Expander.expand!([{%SelfRecursive{}, @rect}])
                   end
    end

    test "raises on non-list input" do
      assert_raise FunctionClauseError, fn -> Expander.expand!(:not_a_list) end
    end

    test "raises on entry that is not a {widget, rect} tuple" do
      assert_raise ArgumentError, ~r/expected \{widget, %ExRatatui.Layout.Rect\{\}\}/, fn ->
        Expander.expand!([:bogus])
      end
    end

    test "raises on entry with non-Rect second element" do
      assert_raise ArgumentError, ~r/expected \{widget, %ExRatatui.Layout.Rect\{\}\}/, fn ->
        Expander.expand!([{%Paragraph{text: "a"}, {0, 0, 5, 1}}])
      end
    end

    test "raises when render/2 returns a non-list" do
      assert_raise ArgumentError,
                   ~r/BadNotList.render\/2 must return a list/,
                   fn -> Expander.expand!([{%BadNotList{}, @rect}]) end
    end

    test "raises when render/2 returns a list entry that is not a tuple" do
      assert_raise ArgumentError,
                   ~r/BadEntry.render\/2 returned an invalid entry/,
                   fn -> Expander.expand!([{%BadEntry{}, @rect}]) end
    end

    test "raises when render/2 returns a tuple with a non-Rect second element" do
      assert_raise ArgumentError,
                   ~r/BadRect.render\/2 returned an invalid entry/,
                   fn -> Expander.expand!([{%BadRect{}, @rect}]) end
    end
  end
end
