defmodule ExRatatui.Theme do
  @moduledoc """
  Named-slot color palette for TUI apps.

  A `%Theme{}` is a pure data struct — a map from semantic slot names
  (`:accent`, `:border`, `:success`, …) to `t:ExRatatui.Style.color/0`
  values. Apps build `%Style{}` values from it via the helpers below
  (`border_style/2`, `text_style/2`, `selection_style/1`) or by
  destructuring slots directly into widget fields.

  This is "Layer A" of the theming work: pure data the app threads
  through its render code by hand. There is no automatic widget
  injection — Block borders don't magically pick up `theme.border`
  unless the app passes it in. A later "Layer B" may add an opt-in
  pass that merges theme defaults into widget structs at render time;
  Layer A stays explicit and dependency-free.

  ## Slots

    * `:primary` — main brand color (titles, highlighted headers)
    * `:accent` — interactive / focused / selected elements
    * `:border` — default border color for unfocused panels
    * `:border_focused` — border color for the focused panel
    * `:surface` — primary background; `nil` means "let the terminal
      decide" and works on both light and dark terminals
    * `:surface_alt` — secondary background (alt rows in tables,
      striped lists, raised panels)
    * `:text` — default foreground for body text
    * `:text_dim` — secondary foreground (hints, placeholders,
      disabled controls)
    * `:success` / `:warning` / `:danger` — status messages and
      severity indicators

  Every slot accepts the full `t:ExRatatui.Style.color/0` shape:
  named atoms (`:cyan`, `:dark_gray`), `{:rgb, r, g, b}`,
  `{:indexed, n}`, or `nil`. Slots default to `nil`, meaning "fall
  back to the terminal default" — apps that don't want to depend on
  any particular palette can drop unused slots.

  ## Composing with widgets

      theme = ExRatatui.Theme.default()

      %ExRatatui.Widgets.Block{
        title: "Search",
        borders: [:all],
        border_style: ExRatatui.Theme.border_style(theme, focused: focused?)
      }

      %ExRatatui.Widgets.List{
        items: results,
        highlight_style: ExRatatui.Theme.selection_style(theme)
      }

  ## Picking a theme

  Two starter constructors ship in the box:

    * `default/0` — terminal-respecting dark-friendly palette
      (cyan accent, transparent surface)
    * `light/0` — same shape with darker text and a light surface,
      suitable for light terminal themes

  Apps with stricter brand requirements compose their own:

      %ExRatatui.Theme{
        primary: {:rgb, 88, 28, 135},
        accent: {:rgb, 245, 158, 11},
        border: :gray,
        border_focused: {:rgb, 245, 158, 11},
        text: :white,
        text_dim: :gray,
        success: :green,
        warning: :yellow,
        danger: :red
      }
  """

  alias ExRatatui.Style

  @type t :: %__MODULE__{
          primary: Style.color() | nil,
          accent: Style.color() | nil,
          border: Style.color() | nil,
          border_focused: Style.color() | nil,
          surface: Style.color() | nil,
          surface_alt: Style.color() | nil,
          text: Style.color() | nil,
          text_dim: Style.color() | nil,
          success: Style.color() | nil,
          warning: Style.color() | nil,
          danger: Style.color() | nil
        }

  defstruct primary: nil,
            accent: nil,
            border: nil,
            border_focused: nil,
            surface: nil,
            surface_alt: nil,
            text: nil,
            text_dim: nil,
            success: nil,
            warning: nil,
            danger: nil

  @doc """
  Returns a terminal-respecting dark-friendly default theme.

  Surfaces are `nil` so the terminal's own background shows through —
  works on both light and dark terminal themes without forcing one.
  Accent is cyan, borders are gray with cyan-on-focus, status uses the
  conventional green / yellow / red triad.

  ## Examples

      iex> theme = ExRatatui.Theme.default()
      iex> theme.accent
      :cyan
      iex> theme.surface
      nil
  """
  @spec default() :: t()
  def default do
    %__MODULE__{
      primary: :cyan,
      accent: :cyan,
      border: :gray,
      border_focused: :cyan,
      surface: nil,
      surface_alt: :dark_gray,
      text: :white,
      text_dim: :gray,
      success: :green,
      warning: :yellow,
      danger: :red
    }
  end

  @doc """
  Returns a light-terminal-friendly variant of `default/0`.

  Text is dark, surface is white, accent stays cyan but borders shift
  to dark_gray for contrast on a light background.

  ## Examples

      iex> theme = ExRatatui.Theme.light()
      iex> theme.text
      :black
      iex> theme.surface
      :white
  """
  @spec light() :: t()
  def light do
    %__MODULE__{
      primary: :blue,
      accent: :cyan,
      border: :dark_gray,
      border_focused: :blue,
      surface: :white,
      surface_alt: :gray,
      text: :black,
      text_dim: :dark_gray,
      success: :green,
      warning: :yellow,
      danger: :red
    }
  end

  @doc """
  Builds a border `%Style{}` from a theme.

  Accepts `focused: true` to swap in `:border_focused`. Defaults to the
  unfocused `:border` slot.

  ## Examples

      iex> theme = ExRatatui.Theme.default()
      iex> ExRatatui.Theme.border_style(theme)
      %ExRatatui.Style{fg: :gray, bg: nil, modifiers: []}
      iex> ExRatatui.Theme.border_style(theme, focused: true)
      %ExRatatui.Style{fg: :cyan, bg: nil, modifiers: []}
  """
  @spec border_style(t(), keyword()) :: Style.t()
  def border_style(%__MODULE__{} = theme, opts \\ []) do
    fg = if Keyword.get(opts, :focused, false), do: theme.border_focused, else: theme.border
    %Style{fg: fg}
  end

  @doc """
  Builds a body-text `%Style{}` from a theme.

  Accepts `dim: true` to use the `:text_dim` slot (hints, placeholders,
  disabled). The background is always `theme.surface`, which is `nil`
  in the default theme.

  ## Examples

      iex> theme = ExRatatui.Theme.default()
      iex> ExRatatui.Theme.text_style(theme)
      %ExRatatui.Style{fg: :white, bg: nil, modifiers: []}
      iex> ExRatatui.Theme.text_style(theme, dim: true)
      %ExRatatui.Style{fg: :gray, bg: nil, modifiers: []}
  """
  @spec text_style(t(), keyword()) :: Style.t()
  def text_style(%__MODULE__{} = theme, opts \\ []) do
    fg = if Keyword.get(opts, :dim, false), do: theme.text_dim, else: theme.text
    %Style{fg: fg, bg: theme.surface}
  end

  @doc """
  Builds a selection-highlight `%Style{}` from a theme.

  The convention is a reversed-style pop: the theme's `:surface` color
  becomes the foreground, the `:accent` becomes the background. Use on
  List `:highlight_style`, Table `:highlight_style`, selected Tabs,
  etc.

  ## Examples

      iex> theme = ExRatatui.Theme.default()
      iex> ExRatatui.Theme.selection_style(theme)
      %ExRatatui.Style{fg: nil, bg: :cyan, modifiers: []}
  """
  @spec selection_style(t()) :: Style.t()
  def selection_style(%__MODULE__{} = theme) do
    %Style{fg: theme.surface, bg: theme.accent}
  end
end
