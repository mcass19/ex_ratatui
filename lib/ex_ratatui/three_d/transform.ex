defmodule ExRatatui.ThreeD.Transform do
  @moduledoc """
  Position, rotation, and scale of a 3D object.

  The model matrix is composed scale, then rotate, then translate.

  ## Fields

    * `:position` - `{x, y, z}` translation (floats), defaults to the origin
    * `:rotation` - one of the rotation forms below, defaults to identity
    * `:scale` - `{x, y, z}` scale factors, defaults to `{1.0, 1.0, 1.0}`

  ## Rotation forms

    * `{:euler_xyz, {rx, ry, rz}}` - intrinsic X then Y then Z, in radians
    * `{:axis_angle, {ax, ay, az}, angle}` - rotation of `angle` radians about
      the (non-zero) axis
    * `{:quat, {x, y, z, w}}` - a raw quaternion

  ## Examples

      iex> %ExRatatui.ThreeD.Transform{}
      %ExRatatui.ThreeD.Transform{
        position: {0.0, 0.0, 0.0},
        rotation: {:quat, {0.0, 0.0, 0.0, 1.0}},
        scale: {1.0, 1.0, 1.0}
      }

      iex> %ExRatatui.ThreeD.Transform{
      ...>   position: {1.0, 0.0, 0.0},
      ...>   rotation: {:axis_angle, {0.0, 1.0, 0.0}, 0.7}
      ...> }.rotation
      {:axis_angle, {0.0, 1.0, 0.0}, 0.7}
  """

  @type vec3 :: {number(), number(), number()}

  @type rotation ::
          {:euler_xyz, vec3()}
          | {:axis_angle, vec3(), number()}
          | {:quat, {number(), number(), number(), number()}}

  @type t :: %__MODULE__{
          position: vec3(),
          rotation: rotation(),
          scale: vec3()
        }

  defstruct position: {0.0, 0.0, 0.0},
            rotation: {:quat, {0.0, 0.0, 0.0, 1.0}},
            scale: {1.0, 1.0, 1.0}
end
