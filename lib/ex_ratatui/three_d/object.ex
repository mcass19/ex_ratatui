defmodule ExRatatui.ThreeD.Object do
  @moduledoc """
  A renderable object: a mesh with a material and a transform.

  ## Fields

    * `:mesh` - an `ExRatatui.ThreeD.Mesh` (defaults to a cube)
    * `:material` - an `ExRatatui.ThreeD.Material`
    * `:transform` - an `ExRatatui.ThreeD.Transform`
    * `:visible` - `false` to skip rendering (defaults to `true`)

  ## Examples

      iex> alias ExRatatui.ThreeD.{Object, Mesh}
      iex> obj = %Object{mesh: Mesh.sphere(8, 12)}
      iex> {obj.mesh.kind, obj.visible}
      {:sphere, true}
  """

  alias ExRatatui.ThreeD.{Material, Mesh, Transform}

  @type t :: %__MODULE__{
          mesh: Mesh.t(),
          material: Material.t(),
          transform: Transform.t(),
          visible: boolean()
        }

  defstruct mesh: %Mesh{},
            material: %Material{},
            transform: %Transform{},
            visible: true
end
