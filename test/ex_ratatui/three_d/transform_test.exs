defmodule ExRatatui.ThreeD.TransformTest do
  use ExUnit.Case, async: true

  alias ExRatatui.ThreeD.Transform

  doctest ExRatatui.ThreeD.Transform

  defp close({ax, ay, az}, {bx, by, bz}) do
    assert_in_delta ax, bx, 1.0e-6
    assert_in_delta ay, by, 1.0e-6
    assert_in_delta az, bz, 1.0e-6
  end

  # Apply a transform to a point using M = T·R·S (mirror of the renderer).
  defp apply_t(%Transform{position: {tx, ty, tz}} = t, {px, py, pz}) do
    {sx, sy, sz} = t.scale
    {qx, qy, qz, qw} = Transform.to_quat(t.rotation)
    {vx, vy, vz} = {px * sx, py * sy, pz * sz}
    {cx, cy, cz} = cross({qx, qy, qz}, {vx, vy, vz})
    {ccx, ccy, ccz} = cross({qx, qy, qz}, {cx, cy, cz})
    rx = vx + 2.0 * qw * cx + 2.0 * ccx
    ry = vy + 2.0 * qw * cy + 2.0 * ccy
    rz = vz + 2.0 * qw * cz + 2.0 * ccz
    {rx + tx, ry + ty, rz + tz}
  end

  defp cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}

  defp close_quat({x, y, z, w}, {ex, ey, ez, ew}) do
    close({x, y, z}, {ex, ey, ez})
    assert_in_delta w, ew, 1.0e-6
  end

  test "to_quat normalizes each rotation form to a unit quaternion" do
    close_quat(Transform.to_quat({:quat, {0.0, 0.0, 0.0, 1.0}}), {0.0, 0.0, 0.0, 1.0})
    {x, y, z, w} = Transform.to_quat({:axis_angle, {0.0, 1.0, 0.0}, :math.pi() / 2})
    close({x, y, z}, {0.0, :math.sin(:math.pi() / 4), 0.0})
    assert_in_delta w, :math.cos(:math.pi() / 4), 1.0e-6
  end

  test "to_quat treats a zero axis as identity" do
    close_quat(Transform.to_quat({:axis_angle, {0.0, 0.0, 0.0}, 1.0}), {0.0, 0.0, 0.0, 1.0})
  end

  test "to_quat normalizes a non-unit quaternion" do
    {x, y, z, w} = Transform.to_quat({:quat, {0.0, 0.0, 0.0, 2.0}})
    close({x, y, z}, {0.0, 0.0, 0.0})
    assert_in_delta w, 1.0, 1.0e-6
  end

  test "to_quat treats a zero quaternion as identity" do
    close_quat(Transform.to_quat({:quat, {0.0, 0.0, 0.0, 0.0}}), {0.0, 0.0, 0.0, 1.0})
  end

  test "to_quat handles euler_xyz as intrinsic X then Y then Z" do
    q = Transform.to_quat({:euler_xyz, {0.0, :math.pi() / 2, 0.0}})
    t = %Transform{rotation: {:quat, q}}
    # +X rotated 90° about Y → -Z
    close(apply_t(t, {1.0, 0.0, 0.0}), {0.0, 0.0, -1.0})
  end

  test "compose with identity parent returns the child (as quat)" do
    child = %Transform{position: {1.0, 2.0, 3.0}, rotation: {:axis_angle, {0.0, 1.0, 0.0}, 0.5}}
    composed = Transform.compose(%Transform{}, child)
    close(composed.position, {1.0, 2.0, 3.0})
    close(apply_t(composed, {1.0, 0.0, 0.0}), apply_t(child, {1.0, 0.0, 0.0}))
  end

  test "compose matches sequential application M_p·M_c for a point" do
    parent = %Transform{
      position: {0.0, 1.0, 0.0},
      rotation: {:axis_angle, {0.0, 0.0, 1.0}, :math.pi() / 2}
    }

    child = %Transform{
      position: {2.0, 0.0, 0.0},
      rotation: {:axis_angle, {0.0, 0.0, 1.0}, :math.pi() / 2}
    }

    composed = Transform.compose(parent, child)

    point = {1.0, 0.0, 0.0}
    expected = apply_t(parent, apply_t(child, point))
    close(apply_t(composed, point), expected)
  end

  test "compose carries child scale through a rigid parent" do
    parent = %Transform{rotation: {:axis_angle, {0.0, 1.0, 0.0}, 0.3}}
    child = %Transform{scale: {2.0, 3.0, 4.0}}
    composed = Transform.compose(parent, child)
    close(composed.scale, {2.0, 3.0, 4.0})
  end
end
