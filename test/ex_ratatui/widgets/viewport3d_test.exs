defmodule ExRatatui.Widgets.Viewport3DTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.ThreeD.{Light, Material, Mesh, Object, Scene}
  alias ExRatatui.Widgets.{Block, Viewport3D}

  doctest ExRatatui.Widgets.Viewport3D

  test "defaults to a braille rasterized empty scene" do
    widget = %Viewport3D{}
    assert widget.render_mode == :braille
    assert widget.pipeline == :rasterize
    assert widget.scene.objects == []
    assert widget.block == nil
  end

  describe "rendering" do
    setup do
      terminal = ExRatatui.init_test_terminal(40, 20)
      on_exit(fn -> Native.restore_terminal(terminal) end)
      %{terminal: terminal}
    end

    @rect %Rect{x: 0, y: 0, width: 40, height: 20}

    defp cube_scene do
      %Scene{
        objects: [%Object{mesh: Mesh.cube(), material: %Material{color: {100, 150, 255}}}],
        lights: [
          Light.ambient({255, 255, 255}, 0.2),
          Light.directional({-1.0, -1.0, -1.0}, {255, 255, 255})
        ]
      }
    end

    test "renders a lit cube as visible geometry in ascii mode", %{terminal: terminal} do
      widget = %Viewport3D{scene: cube_scene(), render_mode: :ascii}

      assert :ok = ExRatatui.draw(terminal, [{widget, @rect}])
      assert String.trim(ExRatatui.get_buffer_content(terminal)) != ""
    end

    test "an empty ascii scene renders blank", %{terminal: terminal} do
      widget = %Viewport3D{render_mode: :ascii}

      assert :ok = ExRatatui.draw(terminal, [{widget, @rect}])
      assert String.trim(ExRatatui.get_buffer_content(terminal)) == ""
    end

    test "renders in braille and half_block modes", %{terminal: terminal} do
      for mode <- [:braille, :half_block] do
        widget = %Viewport3D{scene: cube_scene(), render_mode: mode}
        assert :ok = ExRatatui.draw(terminal, [{widget, @rect}])
      end
    end

    test "renders with the raytrace pipeline", %{terminal: terminal} do
      widget = %Viewport3D{scene: cube_scene(), pipeline: :raytrace, render_mode: :half_block}
      assert :ok = ExRatatui.draw(terminal, [{widget, @rect}])
    end

    test "renders a custom mesh", %{terminal: terminal} do
      mesh = Mesh.new([{-0.5, -0.5, 0.0}, {0.5, -0.5, 0.0}, {0.0, 0.7, 0.0}], [0, 1, 2])

      widget = %Viewport3D{
        scene: %Scene{
          objects: [%Object{mesh: mesh}],
          lights: [Light.ambient({255, 255, 255}, 1.0)]
        }
      }

      assert :ok = ExRatatui.draw(terminal, [{widget, @rect}])
    end

    test "renders a cylinder as visible geometry (winding faces outward)", %{terminal: terminal} do
      scene = %Scene{
        objects: [
          %Object{
            mesh: Mesh.cylinder(24),
            material: %Material{color: {180, 180, 190}},
            transform: %ExRatatui.ThreeD.Transform{scale: {2.0, 2.0, 2.0}}
          }
        ],
        lights: [
          Light.ambient({255, 255, 255}, 0.4),
          Light.directional({0.0, 0.0, -1.0}, {255, 255, 255})
        ]
      }

      widget = %Viewport3D{scene: scene, render_mode: :ascii}

      assert :ok = ExRatatui.draw(terminal, [{widget, @rect}])
      assert String.trim(ExRatatui.get_buffer_content(terminal)) != ""
    end

    test "renders inside a block with a title", %{terminal: terminal} do
      widget = %Viewport3D{scene: cube_scene(), block: %Block{title: "Scene", borders: [:all]}}

      assert :ok = ExRatatui.draw(terminal, [{widget, @rect}])
      assert ExRatatui.get_buffer_content(terminal) =~ "Scene"
    end
  end
end
