# Example: Viewport3D — a custom mesh (a square pyramid) built from raw vertices
# and triangle indices, spinning in place. Normals are computed natively.
# Run with: mix run examples/widgets/viewport3d_custom_mesh.exs
#
# Controls: q = quit
#
# Requires a true-color terminal. This is the path Phase B uses to build shapes
# the engine has no primitive for (such as cylinders for an articulated model).

defmodule Viewport3DCustomMesh do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene, Transform}
  alias ExRatatui.Widgets.{Block, Paragraph, Viewport3D}

  # 4 base corners (y = 0) plus an apex (y = 1). Each side face is wound
  # counter-clockwise as seen from outside so it faces the camera; the two base
  # triangles close the bottom.
  @vertices [
    {-0.6, 0.0, -0.6},
    {0.6, 0.0, -0.6},
    {0.6, 0.0, 0.6},
    {-0.6, 0.0, 0.6},
    {0.0, 1.0, 0.0}
  ]

  @indices [
    3,
    2,
    4,
    2,
    1,
    4,
    1,
    0,
    4,
    0,
    3,
    4,
    0,
    1,
    2,
    0,
    2,
    3
  ]

  @impl true
  def init(_opts), do: {:ok, %{angle: 0.0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [scene_area, help_area] = Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])

    pyramid = %Object{
      mesh: Mesh.new(@vertices, @indices),
      material: %Material{color: {235, 190, 90}},
      transform: %Transform{rotation: {:axis_angle, {0.0, 1.0, 0.0}, state.angle}}
    }

    viewport = %Viewport3D{
      scene: %Scene{
        objects: [pyramid],
        lights: [
          Light.ambient({255, 255, 255}, 0.2),
          Light.directional({-1.0, -1.0, -0.6}, {255, 255, 255}),
          Light.point({1.5, 2.5, 2.0}, {255, 230, 200})
        ],
        background: {10, 10, 14}
      },
      camera: %Camera{position: {2.6, 2.0, 3.2}, target: {0.0, 0.4, 0.0}},
      block: %Block{
        title: " Viewport3D — custom mesh (pyramid) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow}
      }
    }

    help = %Paragraph{text: "  q = quit", style: %Style{fg: :dark_gray}}
    [{viewport, scene_area}, {help, help_area}]
  end

  @impl true
  def update({:event, %Event.Key{code: "q", kind: "press"}}, state), do: {:stop, state}
  def update({:info, :tick}, state), do: {:noreply, %{state | angle: state.angle + 0.04}}
  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state), do: [Subscription.interval(:spin, 33, :tick)]
end

{:ok, pid} = Viewport3DCustomMesh.start_link(name: nil)

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
