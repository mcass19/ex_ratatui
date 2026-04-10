defmodule ExRatatui.SlashCommandsTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Popup
  alias ExRatatui.Widgets.SlashCommands
  alias ExRatatui.Widgets.SlashCommands.Command

  @commands [
    %Command{name: "help", description: "Show help", aliases: ["?"]},
    %Command{name: "clear", description: "Clear chat"},
    %Command{name: "config", description: "Open settings"},
    %Command{name: "quit", description: "Exit the app", aliases: ["exit", "q"]}
  ]

  describe "parse/1" do
    test "detects slash command" do
      assert {:command, "help"} = SlashCommands.parse("/help")
    end

    test "detects partial command" do
      assert {:command, "he"} = SlashCommands.parse("/he")
    end

    test "detects bare slash" do
      assert {:command, ""} = SlashCommands.parse("/")
    end

    test "ignores plain text" do
      assert :no_command = SlashCommands.parse("hello")
    end

    test "ignores empty string" do
      assert :no_command = SlashCommands.parse("")
    end

    test "ignores slash in middle" do
      assert :no_command = SlashCommands.parse("not /a command")
    end

    test "handles leading whitespace" do
      assert {:command, "help"} = SlashCommands.parse("  /help")
    end

    test "stops at first space" do
      assert {:command, "help"} = SlashCommands.parse("/help me")
    end
  end

  describe "match_commands/2" do
    test "exact prefix match" do
      result = SlashCommands.match_commands(@commands, "hel")
      assert length(result) == 1
      assert hd(result).name == "help"
    end

    test "case insensitive" do
      result = SlashCommands.match_commands(@commands, "HEL")
      assert length(result) == 1
      assert hd(result).name == "help"
    end

    test "empty prefix returns all" do
      result = SlashCommands.match_commands(@commands, "")
      assert length(result) == 4
    end

    test "no match returns empty" do
      result = SlashCommands.match_commands(@commands, "xyz")
      assert result == []
    end

    test "matches aliases" do
      result = SlashCommands.match_commands(@commands, "?")
      assert length(result) == 1
      assert hd(result).name == "help"
    end

    test "multiple matches" do
      result = SlashCommands.match_commands(@commands, "c")
      names = Enum.map(result, & &1.name)
      assert "clear" in names
      assert "config" in names
    end
  end

  describe "render_autocomplete/2" do
    test "returns popup with list widget" do
      area = %Rect{x: 0, y: 0, width: 60, height: 20}
      result = SlashCommands.render_autocomplete(@commands, area: area)
      assert [{%Popup{}, ^area}] = result
    end

    test "respects selected index" do
      area = %Rect{x: 0, y: 0, width: 60, height: 20}

      [{%Popup{content: list}, _}] =
        SlashCommands.render_autocomplete(@commands, area: area, selected: 2)

      assert list.selected == 2
    end

    test "empty commands returns popup with empty list" do
      area = %Rect{x: 0, y: 0, width: 60, height: 20}
      [{%Popup{content: list}, _}] = SlashCommands.render_autocomplete([], area: area)
      assert list.items == []
    end
  end
end
