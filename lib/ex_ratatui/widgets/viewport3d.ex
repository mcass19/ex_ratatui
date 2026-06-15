defmodule ExRatatui.Widgets.Viewport3D do
  @moduledoc """
  A 3D viewport widget that renders a scene with software rasterization or ray
  tracing, as true pixel graphics or blitted into terminal cells.

  The widget is pure data: the scene and camera are rebuilt and rendered every
  frame, so it works over every transport. Drive animation and camera movement
  from application state between frames (see `ExRatatui.ThreeD.Camera`).

  A true-color terminal is required, since every mode emits 24-bit colors.

  ## Fields

    * `:scene` - an `ExRatatui.ThreeD.Scene`
    * `:camera` - an `ExRatatui.ThreeD.Camera`
    * `:render_mode` - a pixel-graphics protocol (`:auto`, the default; `:kitty`;
      `:sixel`; `:iterm2`) or a cell-blit mode (`:half_block`, `:braille`, `:ascii`)
    * `:pipeline` - `:rasterize` (default) or `:raytrace`
    * `:block` - optional `ExRatatui.Widgets.Block` container (borders, title)

  ## Render modes

  Pixel-graphics modes render the scene as an image at native terminal resolution
  (crisp, non-blocky) on capable terminals, and fall back to `:braille` where no
  graphics protocol is available (CellSession/Livebook, SSH/distributed without
  passthrough, unsupported terminals):

    * `:auto` - the best protocol the terminal supports, else braille (default)
    * `:kitty` - Kitty graphics protocol (Ghostty, WezTerm, Kitty)
    * `:sixel` - Sixel graphics
    * `:iterm2` - iTerm2 inline images

  Cell-blit modes pack the render into character cells (always available):

    * `:half_block` - one `▀` per cell, fg/bg are the upper/lower pixel
    * `:braille` - supersampled `▀` for anti-aliased edges
    * `:ascii` - a shaded ASCII ramp with colored characters

  ## Examples

      iex> alias ExRatatui.Widgets.Viewport3D
      iex> alias ExRatatui.ThreeD.{Scene, Object, Light, Mesh}
      iex> %Viewport3D{
      ...>   scene: %Scene{
      ...>     objects: [%Object{mesh: Mesh.cube()}],
      ...>     lights: [Light.directional({-1.0, -1.0, -1.0}, {255, 255, 255})]
      ...>   },
      ...>   render_mode: :ascii
      ...> }.render_mode
      :ascii

      iex> %ExRatatui.Widgets.Viewport3D{}.render_mode
      :auto

      iex> %ExRatatui.Widgets.Viewport3D{}.pipeline
      :rasterize
  """

  alias ExRatatui.ThreeD.{Camera, Scene}

  @type render_mode ::
          :auto | :kitty | :sixel | :iterm2 | :half_block | :braille | :ascii
  @type pipeline :: :rasterize | :raytrace

  @type t :: %__MODULE__{
          scene: Scene.t(),
          camera: Camera.t(),
          render_mode: render_mode(),
          pipeline: pipeline(),
          block: ExRatatui.Widgets.Block.t() | nil
        }

  defstruct scene: %Scene{},
            camera: %Camera{},
            render_mode: :auto,
            pipeline: :rasterize,
            block: nil
end
