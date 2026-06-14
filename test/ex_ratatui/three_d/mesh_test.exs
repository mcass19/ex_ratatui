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
end
