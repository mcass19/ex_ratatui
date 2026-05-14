defmodule ExRatatui.Widgets.CodeBlockTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, CodeBlock}

  doctest ExRatatui.Widgets.CodeBlock

  @rect %Rect{x: 0, y: 0, width: 40, height: 10}

  defp encode(widget), do: Bridge.encode_command({widget, @rect}) |> elem(0)

  describe "encode via Bridge.encode_command/1" do
    test "encodes defaults" do
      json = encode(%CodeBlock{content: "x = 1"})

      assert json["type"] == "code_block"
      assert json["content"] == "x = 1"
      assert json["language"] == nil
      assert json["theme"] == "base16-ocean.dark"
      assert json["wrap"] == false
      assert json["scroll_y"] == 0
      assert json["scroll_x"] == 0
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
  end
end
