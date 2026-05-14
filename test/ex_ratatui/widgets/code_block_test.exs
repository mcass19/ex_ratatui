defmodule ExRatatui.Widgets.CodeBlockTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Widgets.{Block, CodeBlock}

  doctest ExRatatui.Widgets.CodeBlock

  @rect %Rect{x: 0, y: 0, width: 40, height: 10}

  defp encode(widget), do: Bridge.encode_command({widget, @rect}) |> elem(0)

  describe "encode via Bridge.encode_command/1" do
    test "encodes defaults" do
      json = encode(%CodeBlock{content: "x = 1"})

      assert json["type"] == "code_block"
      assert json["content"] == "x = 1"
      assert json["theme"] == "base16-ocean.dark"
      assert json["wrap"] == false
      assert json["scroll_y"] == 0
      assert json["scroll_x"] == 0
      refute Map.has_key?(json, "language")
      refute Map.has_key?(json, "block")
    end

    test "resolves the seven curated theme atoms to syntect names" do
      mappings = [
        {:base16_ocean_dark, "base16-ocean.dark"},
        {:base16_ocean_light, "base16-ocean.light"},
        {:base16_eighties_dark, "base16-eighties.dark"},
        {:base16_mocha_dark, "base16-mocha.dark"},
        {:inspired_github, "InspiredGitHub"},
        {:solarized_dark, "Solarized (dark)"},
        {:solarized_light, "Solarized (light)"}
      ]

      for {atom, name} <- mappings do
        json = encode(%CodeBlock{content: "", theme: atom})
        assert json["theme"] == name, "atom #{inspect(atom)} → expected #{name}"
      end
    end

    test "passes raw string themes through unchanged" do
      json = encode(%CodeBlock{content: "", theme: "MyCustomTheme"})
      assert json["theme"] == "MyCustomTheme"
    end

    test "raises on unknown theme atom with a helpful message" do
      err =
        assert_raise ArgumentError, fn ->
          encode(%CodeBlock{content: "", theme: :no_such_theme})
        end

      msg = Exception.message(err)
      assert msg =~ "unknown CodeBlock theme :no_such_theme"
      assert msg =~ ":base16_ocean_dark"
      assert msg =~ ":solarized_light"
    end

    test "includes language when set" do
      assert encode(%CodeBlock{content: "", language: "rust"})["language"] == "rust"
    end

    test "encodes block when present" do
      block = %Block{title: "src", borders: [:all]}
      json = encode(%CodeBlock{content: "", block: block})

      assert is_map(json["block"])
      assert json["block"]["borders"] != nil
    end

    test "encodes custom scroll and wrap" do
      json = encode(%CodeBlock{content: "", scroll: {3, 5}, wrap: true})
      assert json["scroll_y"] == 3
      assert json["scroll_x"] == 5
      assert json["wrap"] == true
    end

    test "encodes line_numbers + starting_line defaults" do
      json = encode(%CodeBlock{content: "x"})
      assert json["line_numbers"] == false
      assert json["starting_line"] == 1
    end

    test "encodes line_numbers when enabled" do
      json = encode(%CodeBlock{content: "x", line_numbers: true, starting_line: 100})
      assert json["line_numbers"] == true
      assert json["starting_line"] == 100
    end

    test "highlight_lines default is an empty list" do
      json = encode(%CodeBlock{content: "x"})
      assert json["highlight_lines"] == []
    end

    test "highlight_lines normalises ints + ranges + dedup + sort" do
      json = encode(%CodeBlock{content: "", highlight_lines: [3, 7..9, 3, 1]})
      assert json["highlight_lines"] == [1, 3, 7, 8, 9]
    end

    test "highlight_lines accepts a single int" do
      json = encode(%CodeBlock{content: "", highlight_lines: [5]})
      assert json["highlight_lines"] == [5]
    end

    test "highlight_lines accepts a single range" do
      json = encode(%CodeBlock{content: "", highlight_lines: [2..4]})
      assert json["highlight_lines"] == [2, 3, 4]
    end

    test "highlight_lines rejects non-positive ints" do
      assert_raise ArgumentError, ~r/invalid highlight_lines entry/, fn ->
        encode(%CodeBlock{content: "", highlight_lines: [0]})
      end
    end

    test "highlight_lines rejects descending ranges" do
      assert_raise ArgumentError, ~r/invalid highlight_lines entry/, fn ->
        encode(%CodeBlock{content: "", highlight_lines: [5..1//-1]})
      end
    end

    test "highlight_lines rejects garbage entries" do
      assert_raise ArgumentError, ~r/invalid highlight_lines entry/, fn ->
        encode(%CodeBlock{content: "", highlight_lines: ["one"]})
      end
    end
  end

  describe "rendering through the native pipeline" do
    setup do
      terminal = ExRatatui.init_test_terminal(60, 8)
      on_exit(fn -> Native.restore_terminal(terminal) end)
      %{terminal: terminal}
    end

    test "renders plain content when language is nil", %{terminal: terminal} do
      widget = %CodeBlock{content: "hello world"}
      rect = %Rect{x: 0, y: 0, width: 60, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{widget, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "hello world"
    end

    test "renders elixir source through the highlighter", %{terminal: terminal} do
      widget = %CodeBlock{
        content: "defmodule X do\n  def hi, do: :ok\nend",
        language: "elixir"
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{widget, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "defmodule"
      assert content =~ "def hi"
    end

    test "renders inside a Block container", %{terminal: terminal} do
      widget = %CodeBlock{
        content: "x = 1",
        language: "elixir",
        block: %Block{title: "snippet", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{widget, rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "snippet"
    end

    test "renders gutter when line_numbers is true", %{terminal: terminal} do
      widget = %CodeBlock{
        content: "a\nb\nc",
        line_numbers: true,
        starting_line: 10
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{widget, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "10 │"
      assert content =~ "11 │"
      assert content =~ "12 │"
    end

    test "renders highlight_lines without erroring", %{terminal: terminal} do
      widget = %CodeBlock{
        content: "a\nb\nc",
        highlight_lines: [2, 3..3]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{widget, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "a"
      assert content =~ "b"
      assert content =~ "c"
    end
  end
end
