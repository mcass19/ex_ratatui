defmodule ExRatatui.ThemeTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.Theme

  alias ExRatatui.Style
  alias ExRatatui.Theme

  describe "default/0" do
    test "all slots are populated with concrete colors except surface" do
      theme = Theme.default()

      assert theme.primary == :cyan
      assert theme.accent == :cyan
      assert theme.border == :gray
      assert theme.border_focused == :cyan
      assert theme.surface == nil
      assert theme.surface_alt == :dark_gray
      assert theme.text == :white
      assert theme.text_dim == :gray
      assert theme.success == :green
      assert theme.warning == :yellow
      assert theme.danger == :red
    end
  end

  describe "light/0" do
    test "uses dark text on white surface, blue borders" do
      theme = Theme.light()

      assert theme.text == :black
      assert theme.surface == :white
      assert theme.border == :dark_gray
      assert theme.border_focused == :blue
    end
  end

  describe "border_style/2" do
    test "returns the unfocused border color by default" do
      theme = Theme.default()
      assert %Style{fg: :gray, bg: nil, modifiers: []} = Theme.border_style(theme)
    end

    test "swaps to border_focused when focused: true" do
      theme = Theme.default()
      assert %Style{fg: :cyan} = Theme.border_style(theme, focused: true)
    end

    test "respects nil slots" do
      theme = %Theme{border: nil, border_focused: nil}
      assert %Style{fg: nil} = Theme.border_style(theme)
      assert %Style{fg: nil} = Theme.border_style(theme, focused: true)
    end
  end

  describe "text_style/2" do
    test "returns text foreground over the surface background" do
      theme = Theme.light()
      assert %Style{fg: :black, bg: :white} = Theme.text_style(theme)
    end

    test "swaps to text_dim when dim: true" do
      theme = Theme.default()
      assert %Style{fg: :gray, bg: nil} = Theme.text_style(theme, dim: true)
    end
  end

  describe "selection_style/1" do
    test "inverts surface and accent" do
      theme = Theme.default()
      assert %Style{fg: nil, bg: :cyan} = Theme.selection_style(theme)
    end

    test "works on a light theme" do
      theme = Theme.light()
      assert %Style{fg: :white, bg: :cyan} = Theme.selection_style(theme)
    end
  end

  describe "custom themes" do
    test "any subset of slots can be set; the rest stay nil" do
      theme = %Theme{accent: {:rgb, 245, 158, 11}, danger: :light_red}

      assert theme.accent == {:rgb, 245, 158, 11}
      assert theme.danger == :light_red
      assert theme.text == nil
      assert theme.border == nil
    end

    test "border_style and text_style work on a partial theme" do
      theme = %Theme{border_focused: :magenta, text: :light_cyan}

      assert %Style{fg: :magenta} = Theme.border_style(theme, focused: true)
      assert %Style{fg: :light_cyan, bg: nil} = Theme.text_style(theme)
    end
  end
end
