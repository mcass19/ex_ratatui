defmodule ExRatatui.Widgets.Viewport3DEncodeTest do
  @moduledoc """
  Bridge encoding and validation for the Viewport3D widget. Exercises the
  wire-format mapping and the ArgumentError contract without a terminal.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Layout.Rect
  alias ExRatatui.ThreeD.{Camera, Light, Mesh, Object, Scene, Transform}
  alias ExRatatui.Widgets.{Block, Viewport3D}

  @rect %Rect{x: 0, y: 0, width: 20, height: 10}

  defp encode(widget) do
    {wire, _rect} = Bridge.encode_command({widget, @rect})
    wire
  end

  describe "happy path" do
    test "encodes a minimal scene with render mode and pipeline as strings" do
      wire = encode(%Viewport3D{render_mode: :ascii, pipeline: :raytrace})

      assert wire["type"] == "viewport3d"
      assert wire["render_mode"] == "ascii"
      assert wire["pipeline"] == "raytrace"
      assert wire["scene"]["objects"] == []
      assert wire["scene"]["background"] == {0, 0, 0}
      refute Map.has_key?(wire["scene"], "sky")
      refute Map.has_key?(wire, "block")
    end

    test "encodes the camera with float coercion" do
      widget = %Viewport3D{camera: %Camera{position: {1, 2, 3}, fov: 1, near: 0, far: 50}}
      camera = encode(widget)["camera"]

      assert camera["position"] == {1.0, 2.0, 3.0}
      assert camera["fov"] == 1.0
      assert camera["near"] == 0.0
      assert camera["far"] == 50.0
    end

    test "encodes a cube object with material and transform defaults" do
      widget = %Viewport3D{scene: %Scene{objects: [%Object{mesh: Mesh.cube()}]}}
      [object] = encode(widget)["scene"]["objects"]

      assert object["mesh"] == %{"kind" => "cube"}
      assert object["visible"] == true
      assert object["material"]["color"] == {200, 200, 200}
      assert object["material"]["diffuse"] == 0.8
      assert object["transform"]["position"] == {0.0, 0.0, 0.0}

      assert object["transform"]["rotation"] == %{
               "kind" => "quat",
               "value" => {0.0, 0.0, 0.0, 1.0}
             }

      assert object["transform"]["scale"] == {1.0, 1.0, 1.0}
    end

    test "encodes plane and sphere meshes" do
      plane = %Viewport3D{scene: %Scene{objects: [%Object{mesh: Mesh.plane()}]}}
      assert [%{"mesh" => %{"kind" => "plane"}}] = encode(plane)["scene"]["objects"]

      sphere = %Viewport3D{scene: %Scene{objects: [%Object{mesh: Mesh.sphere(8, 12)}]}}

      assert [%{"mesh" => %{"kind" => "sphere", "stacks" => 8, "slices" => 12}}] =
               encode(sphere)["scene"]["objects"]
    end

    test "encodes a custom mesh without normals or uvs" do
      mesh = Mesh.new([{0.0, 0.0, 0.0}, {1, 0, 0}, {0, 1, 0}], [0, 1, 2])
      widget = %Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}}
      [%{"mesh" => wire}] = encode(widget)["scene"]["objects"]

      assert wire["kind"] == "custom"
      assert wire["vertices"] == [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}]
      assert wire["indices"] == [0, 1, 2]
      refute Map.has_key?(wire, "normals")
      refute Map.has_key?(wire, "uvs")
    end

    test "encodes a custom mesh with normals and uvs" do
      mesh =
        Mesh.new([{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}], [0, 1, 2],
          normals: [{0, 0, 1}, {0, 0, 1}, {0, 0, 1}],
          uvs: [{0, 0}, {1, 0}, {0, 1}]
        )

      widget = %Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}}
      [%{"mesh" => wire}] = encode(widget)["scene"]["objects"]

      assert wire["normals"] == [{0.0, 0.0, 1.0}, {0.0, 0.0, 1.0}, {0.0, 0.0, 1.0}]
      assert wire["uvs"] == [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]
    end

    test "encodes each light type" do
      scene = %Scene{
        lights: [
          Light.ambient({255, 255, 255}, 0.2),
          Light.directional({-1.0, -1.0, -1.0}, {255, 255, 255}),
          Light.point({2.0, 3.0, 2.0}, {255, 220, 180})
        ]
      }

      [ambient, directional, point] = encode(%Viewport3D{scene: scene})["scene"]["lights"]

      assert ambient == %{"kind" => "ambient", "color" => {255, 255, 255}, "intensity" => 0.2}
      assert directional["kind"] == "directional"
      assert directional["direction"] == {-1.0, -1.0, -1.0}
      assert point["kind"] == "point"
      assert point["position"] == {2.0, 3.0, 2.0}
    end

    test "encodes each rotation form" do
      assert rotation({:euler_xyz, {0.1, 0.2, 0.3}}) ==
               %{"kind" => "euler_xyz", "value" => {0.1, 0.2, 0.3}}

      assert rotation({:axis_angle, {0, 1, 0}, 0.5}) ==
               %{"kind" => "axis_angle", "axis" => {0.0, 1.0, 0.0}, "angle" => 0.5}

      assert rotation({:quat, {0, 0, 0, 1}}) ==
               %{"kind" => "quat", "value" => {0.0, 0.0, 0.0, 1.0}}
    end

    test "encodes a gradient sky and a block" do
      scene = %Scene{sky: %{zenith: {0, 0, 50}, horizon: {120, 120, 160}, ground: {40, 30, 20}}}
      widget = %Viewport3D{scene: scene, block: %Block{title: "Scene", borders: [:all]}}
      wire = encode(widget)

      assert wire["scene"]["sky"]["zenith"] == {0, 0, 50}
      assert wire["scene"]["sky"]["ground"] == {40, 30, 20}
      assert wire["block"]["title"]
    end

    test "honors visible: false" do
      widget = %Viewport3D{scene: %Scene{objects: [%Object{visible: false}]}}
      assert [%{"visible" => false}] = encode(widget)["scene"]["objects"]
    end

    defp rotation(rotation) do
      widget = %Viewport3D{
        scene: %Scene{objects: [%Object{transform: %Transform{rotation: rotation}}]}
      }

      [%{"transform" => %{"rotation" => wire}}] = encode(widget)["scene"]["objects"]
      wire
    end
  end

  describe "validation" do
    test "encodes every supported render mode as a string" do
      for mode <- [:auto, :kitty, :sixel, :iterm2, :half_block, :braille, :ascii] do
        wire = encode(%Viewport3D{render_mode: mode})
        assert wire["render_mode"] == Atom.to_string(mode)
      end
    end

    test "rejects an unknown render mode" do
      assert_raise ArgumentError, ~r/render_mode/, fn ->
        encode(%Viewport3D{render_mode: :wireframe})
      end
    end

    test "rejects an unknown pipeline" do
      assert_raise ArgumentError, ~r/pipeline/, fn ->
        encode(%Viewport3D{pipeline: :raytrace_gpu})
      end
    end

    test "rejects a non-Scene scene" do
      assert_raise ArgumentError, ~r/scene must be a/, fn ->
        encode(%Viewport3D{scene: :nope})
      end
    end

    test "rejects a non-Camera camera" do
      assert_raise ArgumentError, ~r/camera must be a/, fn ->
        encode(%Viewport3D{camera: :nope})
      end
    end

    test "rejects an out-of-range color" do
      assert_raise ArgumentError, ~r/0-255/, fn ->
        encode(%Viewport3D{scene: %Scene{background: {300, 0, 0}}})
      end
    end

    test "rejects a malformed vector" do
      assert_raise ArgumentError, ~r/x, y, z/, fn ->
        encode(%Viewport3D{camera: %Camera{position: {0.0, 0.0}}})
      end
    end

    test "rejects a non-numeric float field" do
      assert_raise ArgumentError, ~r/must be a number/, fn ->
        encode(%Viewport3D{camera: %Camera{fov: :wide}})
      end
    end

    test "rejects a malformed sky" do
      assert_raise ArgumentError, ~r/sky must be/, fn ->
        encode(%Viewport3D{scene: %Scene{sky: %{zenith: {0, 0, 0}}}})
      end
    end

    test "rejects a non-Object scene object" do
      assert_raise ArgumentError, ~r/object must be a/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [:nope]}})
      end
    end

    test "rejects an unknown mesh kind" do
      assert_raise ArgumentError, ~r/mesh must be a/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: %Mesh{kind: :torus}}]}})
      end
    end

    test "rejects non-positive sphere tessellation" do
      mesh = %Mesh{kind: :sphere, stacks: 0, slices: 8}

      assert_raise ArgumentError, ~r/positive integer/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}})
      end
    end

    test "rejects empty custom mesh vertices" do
      mesh = %Mesh{kind: :custom, vertices: [], indices: []}

      assert_raise ArgumentError, ~r/vertices must be a non-empty/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}})
      end
    end

    test "rejects custom indices whose length is not a multiple of 3" do
      mesh = %Mesh{kind: :custom, vertices: [{0.0, 0.0, 0.0}], indices: [0, 0]}

      assert_raise ArgumentError, ~r/multiple of 3/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}})
      end
    end

    test "rejects custom indices out of range" do
      mesh = %Mesh{kind: :custom, vertices: [{0.0, 0.0, 0.0}], indices: [0, 1, 2]}

      assert_raise ArgumentError, ~r/integers in 0\.\.0/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}})
      end
    end

    test "rejects non-list custom indices" do
      mesh = %Mesh{kind: :custom, vertices: [{0.0, 0.0, 0.0}], indices: :nope}

      assert_raise ArgumentError, ~r/indices must be a list/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}})
      end
    end

    test "rejects normals that do not match the vertex count" do
      mesh =
        Mesh.new([{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}], [0, 1, 2],
          normals: [{0, 0, 1}]
        )

      assert_raise ArgumentError, ~r/normals must be a list matching/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}})
      end
    end

    test "rejects uvs that do not match the vertex count" do
      mesh =
        Mesh.new([{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}], [0, 1, 2], uvs: [{0, 0}])

      assert_raise ArgumentError, ~r/uvs must be a list matching/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}})
      end
    end

    test "rejects a malformed uv pair" do
      mesh =
        Mesh.new([{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}], [0, 1, 2],
          uvs: [{0, 0}, {1, 0}, :bad]
        )

      assert_raise ArgumentError, ~r/uv must be a/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{mesh: mesh}]}})
      end
    end

    test "rejects a non-Material material" do
      assert_raise ArgumentError, ~r/material must be a/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{material: :nope}]}})
      end
    end

    test "rejects a non-Transform transform" do
      assert_raise ArgumentError, ~r/transform must be a/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{transform: :nope}]}})
      end
    end

    test "rejects an unknown rotation form" do
      transform = %Transform{rotation: {:matrix, :whatever}}

      assert_raise ArgumentError, ~r/rotation must be/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{transform: transform}]}})
      end
    end

    test "rejects a quaternion with non-numeric components" do
      transform = %Transform{rotation: {:quat, {0, 0, 0, :one}}}

      assert_raise ArgumentError, ~r/rotation must be/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{transform: transform}]}})
      end
    end

    test "rejects an unknown light type" do
      assert_raise ArgumentError, ~r/light :type must be/, fn ->
        encode(%Viewport3D{scene: %Scene{lights: [%Light{type: :spot}]}})
      end
    end

    test "rejects a non-Light scene light" do
      assert_raise ArgumentError, ~r/light must be a/, fn ->
        encode(%Viewport3D{scene: %Scene{lights: [:nope]}})
      end
    end

    test "rejects a non-boolean visible flag" do
      assert_raise ArgumentError, ~r/visible/, fn ->
        encode(%Viewport3D{scene: %Scene{objects: [%Object{visible: :yes}]}})
      end
    end
  end
end
