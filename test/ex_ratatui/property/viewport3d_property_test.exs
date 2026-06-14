defmodule ExRatatui.Property.Viewport3DPropertyTest do
  @moduledoc """
  Property invariants for the Viewport3D widget:

    1. `ExRatatui.Bridge.encode_commands!/1` accepts any generated valid
       scene without raising.
    2. `ExRatatui.CellSession.draw/2` over arbitrary valid scenes never
       panics the renderer and yields a `width * height` snapshot.

  Generators stay small (few objects/lights, low sphere tessellation) and
  the render property uses the rasterizer to keep runtime predictable; the
  encode property still exercises both pipelines.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.Bridge
  alias ExRatatui.CellSession
  alias ExRatatui.Layout.Rect
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene}
  alias ExRatatui.Widgets.Viewport3D

  defp coord, do: float(min: -5.0, max: 5.0)
  defp vec3_gen, do: {coord(), coord(), coord()}
  defp channel, do: integer(0..255)
  defp rgb_gen, do: {channel(), channel(), channel()}
  defp unit, do: float(min: 0.0, max: 1.0)

  defp mesh_gen do
    one_of([
      constant(Mesh.cube()),
      constant(Mesh.plane()),
      bind({integer(2..10), integer(3..16)}, fn {stacks, slices} ->
        constant(Mesh.sphere(stacks, slices))
      end),
      bind({vec3_gen(), vec3_gen(), vec3_gen()}, fn {a, b, c} ->
        constant(Mesh.new([a, b, c], [0, 1, 2]))
      end)
    ])
  end

  defp material_gen do
    bind({rgb_gen(), unit(), unit(), unit(), float(min: 1.0, max: 128.0)}, fn {c, a, d, s, sh} ->
      constant(%Material{color: c, ambient: a, diffuse: d, specular: s, shininess: sh})
    end)
  end

  defp rotation_gen do
    one_of([
      bind(vec3_gen(), &constant({:euler_xyz, &1})),
      bind({{constant(0.0), constant(1.0), constant(0.0)}, coord()}, fn {axis, angle} ->
        constant({:axis_angle, axis, angle})
      end),
      constant({:quat, {0.0, 0.0, 0.0, 1.0}})
    ])
  end

  defp transform_gen do
    bind({vec3_gen(), rotation_gen()}, fn {position, rotation} ->
      constant(%ExRatatui.ThreeD.Transform{position: position, rotation: rotation})
    end)
  end

  defp object_gen do
    bind({mesh_gen(), material_gen(), transform_gen(), boolean()}, fn {mesh, mat, tf, vis} ->
      constant(%Object{mesh: mesh, material: mat, transform: tf, visible: vis})
    end)
  end

  defp light_gen do
    one_of([
      bind({rgb_gen(), unit()}, fn {c, i} -> constant(Light.ambient(c, i)) end),
      bind({vec3_gen(), rgb_gen()}, fn {d, c} -> constant(Light.directional(d, c)) end),
      bind({vec3_gen(), rgb_gen()}, fn {p, c} -> constant(Light.point(p, c)) end)
    ])
  end

  defp camera_gen do
    bind({vec3_gen(), rgb_gen()}, fn {position, _} ->
      constant(%Camera{position: position, target: {0.0, 0.0, 0.0}})
    end)
  end

  defp scene_gen do
    bind({list_of(object_gen(), max_length: 3), list_of(light_gen(), max_length: 3)}, fn {objs,
                                                                                          lights} ->
      bind(rgb_gen(), fn bg -> constant(%Scene{objects: objs, lights: lights, background: bg}) end)
    end)
  end

  defp viewport_gen(pipelines) do
    bind({scene_gen(), camera_gen()}, fn {scene, camera} ->
      bind({member_of([:half_block, :braille, :ascii]), member_of(pipelines)}, fn {mode, pipeline} ->
        constant(%Viewport3D{scene: scene, camera: camera, render_mode: mode, pipeline: pipeline})
      end)
    end)
  end

  defp rect_gen do
    bind({integer(1..40), integer(1..20)}, fn {w, h} ->
      constant(%Rect{x: 0, y: 0, width: w, height: h})
    end)
  end

  property "encode_commands! accepts any valid scene at any rect" do
    check all(widget <- viewport_gen([:rasterize, :raytrace]), rect <- rect_gen()) do
      assert [{wire, _rect}] = Bridge.encode_commands!([{widget, rect}])
      assert wire["type"] == "viewport3d"
    end
  end

  property "CellSession render yields a width*height snapshot" do
    check all(
            widget <- viewport_gen([:rasterize]),
            width <- integer(1..40),
            height <- integer(1..20)
          ) do
      session = CellSession.new(width, height)
      rect = %Rect{x: 0, y: 0, width: width, height: height}

      try do
        assert :ok = CellSession.draw(session, [{widget, rect}])
        snapshot = CellSession.take_cells(session)
        assert length(snapshot.cells) == width * height
      after
        CellSession.close(session)
      end
    end
  end
end
