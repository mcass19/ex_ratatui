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

  @doc """
  Normalize any rotation form to a unit quaternion `{x, y, z, w}`.
  """
  @spec to_quat(rotation()) :: {float(), float(), float(), float()}
  def to_quat({:quat, {x, y, z, w}}), do: normalize_quat({x, y, z, w})

  def to_quat({:axis_angle, {ax, ay, az}, angle}) do
    len = :math.sqrt(ax * ax + ay * ay + az * az)

    if len == 0.0 do
      {0.0, 0.0, 0.0, 1.0}
    else
      half = angle / 2.0
      s = :math.sin(half) / len
      {ax * s, ay * s, az * s, :math.cos(half)}
    end
  end

  def to_quat({:euler_xyz, {rx, ry, rz}}) do
    # Intrinsic X then Y then Z: q = qx * qy * qz.
    qx = to_quat({:axis_angle, {1.0, 0.0, 0.0}, rx})
    qy = to_quat({:axis_angle, {0.0, 1.0, 0.0}, ry})
    qz = to_quat({:axis_angle, {0.0, 0.0, 1.0}, rz})
    quat_mul(quat_mul(qx, qy), qz)
  end

  @doc """
  Compose two transforms: `compose(parent, child)` is the single transform equal
  to the matrix product `M_parent · M_child` (parent applied outermost).

  Exact when `parent.scale == {1.0, 1.0, 1.0}` (the rigid-frame contract used by
  `ExRatatui.ThreeD.Node`); for a non-uniform parent scale with a rotated child the
  result is approximate. The result rotation is always `{:quat, _}`.

  ## Examples

      iex> alias ExRatatui.ThreeD.Transform
      iex> parent = %Transform{position: {1.0, 0.0, 0.0}}
      iex> child = %Transform{position: {0.0, 2.0, 0.0}}
      iex> Transform.compose(parent, child).position
      {1.0, 2.0, 0.0}
  """
  @spec compose(t(), t()) :: t()
  def compose(%__MODULE__{} = parent, %__MODULE__{} = child) do
    pq = to_quat(parent.rotation)
    {psx, psy, psz} = parent.scale
    {cpx, cpy, cpz} = child.position
    {ppx, ppy, ppz} = parent.position
    # parent_pos + R_parent * (S_parent ⊙ child_pos)
    {rx, ry, rz} = quat_rotate(pq, {cpx * psx, cpy * psy, cpz * psz})
    {csx, csy, csz} = child.scale

    %__MODULE__{
      position: {ppx + rx, ppy + ry, ppz + rz},
      rotation: {:quat, quat_mul(pq, to_quat(child.rotation))},
      scale: {psx * csx, psy * csy, psz * csz}
    }
  end

  defp quat_mul({x1, y1, z1, w1}, {x2, y2, z2, w2}) do
    {
      w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
      w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
      w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
      w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2
    }
  end

  defp quat_rotate({qx, qy, qz, qw}, {vx, vy, vz}) do
    {cx, cy, cz} = cross({qx, qy, qz}, {vx, vy, vz})
    {ccx, ccy, ccz} = cross({qx, qy, qz}, {cx, cy, cz})

    {vx + 2.0 * qw * cx + 2.0 * ccx, vy + 2.0 * qw * cy + 2.0 * ccy,
     vz + 2.0 * qw * cz + 2.0 * ccz}
  end

  defp cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}

  defp normalize_quat({x, y, z, w}) do
    len = :math.sqrt(x * x + y * y + z * z + w * w)

    if len == 0.0 do
      {0.0, 0.0, 0.0, 1.0}
    else
      {x / len, y / len, z / len, w / len}
    end
  end
end
