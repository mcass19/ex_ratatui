defmodule ExRatatui.ThreeD.MeshTest do
  use ExUnit.Case, async: true

  alias ExRatatui.ThreeD.Mesh

  doctest ExRatatui.ThreeD.Mesh

  test "sphere/2 rejects non-positive tessellation" do
    assert_raise FunctionClauseError, fn -> Mesh.sphere(0, 8) end
    assert_raise FunctionClauseError, fn -> Mesh.sphere(8, 0) end
  end

  test "new/3 carries optional normals and uvs" do
    mesh =
      Mesh.new(
        [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}],
        [0, 1, 2],
        normals: [{0.0, 0.0, 1.0}, {0.0, 0.0, 1.0}, {0.0, 0.0, 1.0}],
        uvs: [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]
      )

    assert mesh.kind == :custom
    assert mesh.normals == [{0.0, 0.0, 1.0}, {0.0, 0.0, 1.0}, {0.0, 0.0, 1.0}]
    assert mesh.uvs == [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]
  end

  test "new/2 leaves normals and uvs unset" do
    mesh = Mesh.new([{0.0, 0.0, 0.0}], [0, 0, 0])
    assert mesh.normals == nil
    assert mesh.uvs == nil
  end

  test "cylinder/1 builds a custom mesh with caps and matching normals" do
    mesh = Mesh.cylinder(24)
    assert mesh.kind == :custom
    # 2*segments side + 2*segments cap-ring + 2 centers
    assert length(mesh.vertices) == 2 * 24 + 2 * 24 + 2
    assert length(mesh.normals) == length(mesh.vertices)
    assert rem(length(mesh.indices), 3) == 0
    n = length(mesh.vertices)
    assert Enum.all?(mesh.indices, &(&1 >= 0 and &1 < n))
  end

  test "cylinder/0 defaults to 24 segments" do
    assert Mesh.cylinder() == Mesh.cylinder(24)
  end

  test "cylinder/1 fits in the unit cube (radius 0.5, height 1.0)" do
    mesh = Mesh.cylinder(12)

    {xs, ys, zs} =
      Enum.reduce(mesh.vertices, {[], [], []}, fn {x, y, z}, {ax, ay, az} ->
        {[x | ax], [y | ay], [z | az]}
      end)

    assert_in_delta Enum.max(xs), 0.5, 1.0e-9
    assert_in_delta Enum.min(ys), -0.5, 1.0e-9
    assert_in_delta Enum.max(ys), 0.5, 1.0e-9
    assert_in_delta Enum.max(zs), 0.5, 1.0e-9
  end

  test "cylinder/1 rejects fewer than 3 segments" do
    assert_raise FunctionClauseError, fn -> Mesh.cylinder(2) end
  end
end
