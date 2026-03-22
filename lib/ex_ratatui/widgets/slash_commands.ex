defmodule ExRatatui.Widgets.SlashCommands do
  @moduledoc """
  Slash command parsing and autocomplete popup rendering.

  Provides utilities for detecting `/command` prefixes in text input,
  matching against a list of registered commands, and rendering an
  autocomplete popup with the `Popup` + `List` widgets.

  ## Usage

      commands = [
        %SlashCommands.Command{name: "help", description: "Show help"},
        %SlashCommands.Command{name: "clear", description: "Clear chat"},
        %SlashCommands.Command{name: "quit", description: "Exit the app"}
      ]

      case SlashCommands.parse(input_text) do
        {:command, prefix} ->
          matched = SlashCommands.match_commands(commands, prefix)
          popup_widgets = SlashCommands.render_autocomplete(matched, area: area)
          # Append popup_widgets to your render list

        :no_command ->
          # No slash command detected
      end
  """

  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, List, Popup}

  defmodule Command do
    @moduledoc """
    A slash command definition with name, description, and optional aliases.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            description: String.t(),
            aliases: [String.t()]
          }

    defstruct name: "", description: "", aliases: []
  end

  @doc """
  Parses input text to detect a slash command prefix.

  Returns `{:command, prefix}` if the text starts with `/` (after optional
  leading whitespace), or `:no_command` otherwise. The prefix is the text
  between `/` and the first space.

  ## Examples

      iex> ExRatatui.Widgets.SlashCommands.parse("/help")
      {:command, "help"}

      iex> ExRatatui.Widgets.SlashCommands.parse("/he")
      {:command, "he"}

      iex> ExRatatui.Widgets.SlashCommands.parse("/")
      {:command, ""}

      iex> ExRatatui.Widgets.SlashCommands.parse("hello")
      :no_command

      iex> ExRatatui.Widgets.SlashCommands.parse("")
      :no_command
  """
  @spec parse(String.t()) :: {:command, String.t()} | :no_command
  def parse(text) when is_binary(text) do
    text = String.trim_leading(text)

    case Regex.run(~r/^\/(\S*)/, text) do
      [_, prefix] -> {:command, prefix}
      _ -> :no_command
    end
  end

  @doc """
  Filters commands whose name or aliases start with the given prefix.

  Case-insensitive matching. An empty prefix matches all commands.

  ## Examples

      iex> cmds = [%ExRatatui.Widgets.SlashCommands.Command{name: "help"}, %ExRatatui.Widgets.SlashCommands.Command{name: "clear"}]
      iex> ExRatatui.Widgets.SlashCommands.match_commands(cmds, "hel")
      [%ExRatatui.Widgets.SlashCommands.Command{name: "help", description: "", aliases: []}]

      iex> cmds = [%ExRatatui.Widgets.SlashCommands.Command{name: "help"}]
      iex> ExRatatui.Widgets.SlashCommands.match_commands(cmds, "")
      [%ExRatatui.Widgets.SlashCommands.Command{name: "help", description: "", aliases: []}]
  """
  @spec match_commands([Command.t()], String.t()) :: [Command.t()]
  def match_commands(commands, prefix) when is_list(commands) and is_binary(prefix) do
    prefix_down = String.downcase(prefix)

    Enum.filter(commands, fn cmd ->
      String.starts_with?(String.downcase(cmd.name), prefix_down) or
        Enum.any?(cmd.aliases, &String.starts_with?(String.downcase(&1), prefix_down))
    end)
  end

  @doc """
  Builds a popup widget list for autocomplete display.

  Returns a list of `{widget, rect}` tuples that can be appended to
  your render output. Uses `Popup` + `List` widgets.

  ## Options

    * `:area` (required) — the `Rect` to position the popup in
    * `:selected` — zero-based index of the selected command (default `0`)
    * `:highlight_style` — style for the selected item
    * `:style` — style for non-selected items
    * `:percent_width` — popup width as percentage (default `50`)
    * `:percent_height` — popup height as percentage (default `40`)
  """
  @spec render_autocomplete([Command.t()], keyword()) :: [
          {ExRatatui.widget(), ExRatatui.Layout.Rect.t()}
        ]
  def render_autocomplete(matched_commands, opts) do
    area = Keyword.fetch!(opts, :area)

    items =
      Enum.map(matched_commands, fn cmd ->
        "/#{cmd.name} — #{cmd.description}"
      end)

    list = %List{
      items: items,
      selected: Keyword.get(opts, :selected, 0),
      highlight_style: Keyword.get(opts, :highlight_style, %Style{fg: :cyan, modifiers: [:bold]}),
      style: Keyword.get(opts, :style, %Style{fg: :white})
    }

    popup = %Popup{
      content: list,
      block: %Block{
        title: "Commands",
        borders: [:all],
        border_type: :rounded
      },
      percent_width: Keyword.get(opts, :percent_width, 50),
      percent_height: Keyword.get(opts, :percent_height, 40)
    }

    [{popup, area}]
  end
end
