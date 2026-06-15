defmodule ExRatatui.ThreeD.Node do
  @moduledoc """
  A node in a transform hierarchy that flattens to a flat `ExRatatui.ThreeD.Scene`.

  `ExRatatui.ThreeD.Scene` has no scene graph — every object carries its own
  world-space transform. `Node` lets an application express an articulated model
  as a tree of local transforms and bake it into world-space objects each frame.

  ## Fields

    * `:transform` - the node's local frame, relative to its parent
    * `:visual` - an optional `ExRatatui.ThreeD.Object` rendered at this node; the
      object's own transform is treated as a local offset/scale within the frame
    * `:children` - child nodes

  ## Composition contract

  Frames compose via `ExRatatui.ThreeD.Transform.compose/2`. Keep intermediate
  nodes **rigid** (`scale: {1.0, 1.0, 1.0}`) and put scale only on leaf `visual`
  objects; then every baked object is exactly one `Transform` (no shear).

  ## Examples

      iex> alias ExRatatui.ThreeD.{Node, Object, Mesh}
      iex> tree = %Node{visual: %Object{mesh: Mesh.cube()}}
      iex> length(ExRatatui.ThreeD.Node.flatten(tree))
      1
  """

  alias ExRatatui.ThreeD.{Object, Scene, Transform}

  @type t :: %__MODULE__{
          transform: Transform.t(),
          visual: Object.t() | nil,
          children: [t()]
        }

  defstruct transform: %Transform{}, visual: nil, children: []

  @doc """
  Flatten the tree into a list of world-space `ExRatatui.ThreeD.Object`s.
  """
  @spec flatten(t()) :: [Object.t()]
  def flatten(%__MODULE__{} = node), do: do_flatten(node, %Transform{})

  defp do_flatten(%__MODULE__{} = node, parent_world) do
    world = Transform.compose(parent_world, node.transform)
    emit(node.visual, world) ++ Enum.flat_map(node.children, &do_flatten(&1, world))
  end

  defp emit(nil, _world), do: []

  defp emit(%Object{} = object, world),
    do: [%{object | transform: Transform.compose(world, object.transform)}]

  @doc """
  Flatten the tree and wrap it in a `Scene`.

  Options: `:lights`, `:background`, `:sky` (passed straight to the `Scene`).
  """
  @spec to_scene(t(), keyword()) :: Scene.t()
  def to_scene(%__MODULE__{} = node, opts \\ []) do
    %Scene{
      objects: flatten(node),
      lights: Keyword.get(opts, :lights, []),
      background: Keyword.get(opts, :background, {0, 0, 0}),
      sky: Keyword.get(opts, :sky)
    }
  end
end
