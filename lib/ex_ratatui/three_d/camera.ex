defmodule ExRatatui.ThreeD.Camera do
  @moduledoc """
  A perspective camera looking at a target.

  The camera is plain data; `orbit/3` and `zoom/2` are pure helpers that return a
  new camera, so an application drives them from key events and keeps the result
  in its own state.

  ## Fields

    * `:position` - `{x, y, z}` eye position
    * `:target` - `{x, y, z}` look-at point
    * `:up` - `{x, y, z}` up vector (defaults to `+Y`)
    * `:fov` - vertical field of view in radians (defaults to `pi/4`)
    * `:near` - near clip plane (defaults to `0.1`)
    * `:far` - far clip plane (defaults to `100.0`)

  ## Examples

      iex> %ExRatatui.ThreeD.Camera{}
      %ExRatatui.ThreeD.Camera{
        position: {0.0, 2.0, 5.0},
        target: {0.0, 0.0, 0.0},
        up: {0.0, 1.0, 0.0},
        fov: 0.7853981633974483,
        near: 0.1,
        far: 100.0
      }

      iex> cam = %ExRatatui.ThreeD.Camera{position: {0.0, 0.0, 5.0}}
      iex> ExRatatui.ThreeD.Camera.zoom(cam, -2.0).position
      {0.0, 0.0, 3.0}
  """

  @default_fov :math.pi() / 4
  @min_pitch 0.05
  @min_radius 0.5

  @type vec3 :: {number(), number(), number()}

  @type t :: %__MODULE__{
          position: vec3(),
          target: vec3(),
          up: vec3(),
          fov: float(),
          near: float(),
          far: float()
        }

  defstruct position: {0.0, 2.0, 5.0},
            target: {0.0, 0.0, 0.0},
            up: {0.0, 1.0, 0.0},
            fov: @default_fov,
            near: 0.1,
            far: 100.0

  @doc """
  Orbit the camera around its target by `yaw` and `pitch` deltas (radians).

  Pitch is clamped to avoid gimbal lock at the poles.
  """
  @spec orbit(t(), number(), number()) :: t()
  def orbit(%__MODULE__{position: {px, py, pz}, target: {tx, ty, tz}} = camera, yaw, pitch) do
    {ox, oy, oz} = {px - tx, py - ty, pz - tz}
    radius = :math.sqrt(ox * ox + oy * oy + oz * oz)

    theta = :math.atan2(oz, ox) + yaw
    phi = clamp(:math.acos(oy / radius) + pitch, @min_pitch, :math.pi() - @min_pitch)

    position = {
      tx + radius * :math.sin(phi) * :math.cos(theta),
      ty + radius * :math.cos(phi),
      tz + radius * :math.sin(phi) * :math.sin(theta)
    }

    %{camera | position: position}
  end

  @doc """
  Move the camera toward or away from its target along the view direction.

  A positive `delta` moves farther; the distance is clamped to a small minimum.
  """
  @spec zoom(t(), number()) :: t()
  def zoom(%__MODULE__{position: {px, py, pz}, target: {tx, ty, tz}} = camera, delta) do
    {ox, oy, oz} = {px - tx, py - ty, pz - tz}
    length = :math.sqrt(ox * ox + oy * oy + oz * oz)
    radius = max(length + delta, @min_radius)
    {nx, ny, nz} = normalize({ox, oy, oz}, length)

    %{camera | position: {tx + nx * radius, ty + ny * radius, tz + nz * radius}}
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp normalize({x, y, z}, length) when length > 0.0, do: {x / length, y / length, z / length}
  defp normalize(_vector, _length), do: {0.0, 0.0, 0.0}
end
