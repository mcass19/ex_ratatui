defmodule ExRatatui.Widgets.Viewport3D do
  @moduledoc """
  A 3D viewport widget that renders a scene with software rasterization or ray
  tracing, blitted into terminal cells.

  The widget is pure data: the scene and camera are rebuilt and rendered every
  frame, so it works over every transport. Drive animation and camera movement
  from application state between frames (see `ExRatatui.ThreeD.Camera`).

  A true-color terminal is required, since every blit mode emits 24-bit colors.

  ## Fields

    * `:scene` - an `ExRatatui.ThreeD.Scene`
    * `:camera` - an `ExRatatui.ThreeD.Camera`
    * `:render_mode` - `:half_block`, `:braille` (default), or `:ascii`
    * `:pipeline` - `:rasterize` (default) or `:raytrace`
    * `:block` - optional `ExRatatui.Widgets.Block` container (borders, title)

  ## Render modes

    * `:half_block` - one `▀` per cell, fg/bg are the upper/lower pixel
    * `:braille` - supersampled `▀` for anti-aliased edges (default)
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

      iex> %ExRatatui.Widgets.Viewport3D{}.pipeline
      :rasterize
  """

  alias ExRatatui.ThreeD.{Camera, Scene}

  @type render_mode :: :half_block | :braille | :ascii
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
            render_mode: :braille,
            pipeline: :rasterize,
            block: nil
end
