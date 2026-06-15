defmodule ExRatatui.ThreeD.NodeTest do
  use ExUnit.Case, async: true

  alias ExRatatui.ThreeD.{Light, Mesh, Node, Object, Scene, Transform}

  doctest ExRatatui.ThreeD.Node

  defp close({ax, ay, az}, {bx, by, bz}) do
    assert_in_delta ax, bx, 1.0e-6
    assert_in_delta ay, by, 1.0e-6
    assert_in_delta az, bz, 1.0e-6
  end

  test "flatten emits one object per node that has a visual" do
    tree = %Node{
      transform: %Transform{position: {1.0, 0.0, 0.0}},
      visual: %Object{mesh: Mesh.cube()},
      children: [
        %Node{
          transform: %Transform{position: {0.0, 2.0, 0.0}},
          visual: %Object{mesh: Mesh.sphere()}
        },
        %Node{transform: %Transform{position: {5.0, 0.0, 0.0}}, children: []}
      ]
    }

    objects = Node.flatten(tree)
    assert length(objects) == 2
  end

  test "flatten bakes world position down the chain" do
    tree = %Node{
      transform: %Transform{position: {1.0, 0.0, 0.0}},
      children: [
        %Node{
          transform: %Transform{position: {0.0, 1.0, 0.0}},
          visual: %Object{mesh: Mesh.cube()}
        }
      ]
    }

    [obj] = Node.flatten(tree)
    close(obj.transform.position, {1.0, 1.0, 0.0})
  end

  test "flatten composes a parent rotation into a child's world position" do
    tree = %Node{
      transform: %Transform{rotation: {:axis_angle, {0.0, 0.0, 1.0}, :math.pi() / 2}},
      children: [
        %Node{
          transform: %Transform{position: {1.0, 0.0, 0.0}},
          visual: %Object{mesh: Mesh.cube()}
        }
      ]
    }

    [obj] = Node.flatten(tree)
    # +X rotated 90° about Z → +Y
    close(obj.transform.position, {0.0, 1.0, 0.0})
  end

  test "flatten composes a node's visual offset within its world frame" do
    tree = %Node{
      transform: %Transform{position: {2.0, 0.0, 0.0}},
      visual: %Object{
        mesh: Mesh.cube(),
        transform: %Transform{position: {0.0, 1.0, 0.0}, scale: {3.0, 3.0, 3.0}}
      }
    }

    [obj] = Node.flatten(tree)
    close(obj.transform.position, {2.0, 1.0, 0.0})
    close(obj.transform.scale, {3.0, 3.0, 3.0})
  end

  test "to_scene wraps flattened objects with lights and background" do
    tree = %Node{visual: %Object{mesh: Mesh.cube()}}

    scene =
      Node.to_scene(tree, lights: [Light.ambient({255, 255, 255}, 0.2)], background: {1, 2, 3})

    assert %Scene{} = scene
    assert length(scene.objects) == 1
    assert scene.background == {1, 2, 3}
    assert length(scene.lights) == 1
  end

  test "to_scene defaults lights, background, and sky" do
    scene = Node.to_scene(%Node{})
    assert scene.objects == []
    assert scene.lights == []
    assert scene.background == {0, 0, 0}
    assert scene.sky == nil
  end
end
