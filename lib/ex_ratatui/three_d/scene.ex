defmodule ExRatatui.ThreeD.Scene do
  @moduledoc """
  A 3D scene: a flat list of objects and lights with a background.

  The scene has no scene graph; every object carries its own world-space
  transform. Compose hierarchies (such as articulated models) in application
  code by computing each object's transform before building the scene.

  ## Fields

    * `:objects` - list of `ExRatatui.ThreeD.Object`
    * `:lights` - list of `ExRatatui.ThreeD.Light`
    * `:background` - `{r, g, b}` clear color (defaults to black)
    * `:sky` - optional gradient sky `%{zenith: rgb, horizon: rgb, ground: rgb}`,
      sampled by the raytrace pipeline; `nil` to use the flat background

  ## Examples

      iex> alias ExRatatui.ThreeD.{Scene, Object, Light, Mesh}
      iex> scene = %Scene{
      ...>   objects: [%Object{mesh: Mesh.cube()}],
      ...>   lights: [Light.ambient({255, 255, 255}, 0.2)],
      ...>   background: {10, 10, 20}
      ...> }
      iex> length(scene.objects)
      1
  """

  alias ExRatatui.ThreeD.{Light, Object}

  @type rgb :: {0..255, 0..255, 0..255}
  @type sky :: %{zenith: rgb(), horizon: rgb(), ground: rgb()} | nil

  @type t :: %__MODULE__{
          objects: [Object.t()],
          lights: [Light.t()],
          background: rgb(),
          sky: sky()
        }

  defstruct objects: [],
            lights: [],
            background: {0, 0, 0},
            sky: nil
end
