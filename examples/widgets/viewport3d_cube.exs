# Example: Viewport3D — a single lit cube spinning in 3D, rasterized into the terminal.
# Run with: mix run examples/widgets/viewport3d_cube.exs
#
# Controls: q = quit
#
# Requires a true-color terminal.
#
# Uses the reducer runtime: a Subscription.interval advances the rotation angle,
# and render/2 rebuilds the scene each frame from that angle.

defmodule Viewport3DCube do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene, Transform}
  alias ExRatatui.Widgets.{Block, Paragraph, Viewport3D}

  @impl true
  def init(_opts), do: {:ok, %{angle: 0.0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [scene_area, help_area] = Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])

    cube = %Object{
      mesh: Mesh.cube(),
      material: %Material{color: {100, 150, 255}},
      transform: %Transform{rotation: {:euler_xyz, {state.angle * 0.3, state.angle * 0.8, 0.0}}}
    }

    viewport = %Viewport3D{
      scene: %Scene{
        objects: [cube],
        lights: [
          Light.ambient({255, 255, 255}, 0.15),
          Light.directional({-1.0, -1.0, -1.0}, {255, 255, 255}),
          Light.point({2.0, 3.0, 2.0}, {255, 220, 180})
        ],
        background: {8, 8, 16}
      },
      camera: %Camera{position: {3.0, 2.5, 4.0}, target: {0.0, 0.0, 0.0}},
      block: %Block{
        title: " Viewport3D — spinning cube ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    help = %Paragraph{text: "  q = quit", style: %Style{fg: :dark_gray}}
    [{viewport, scene_area}, {help, help_area}]
  end

  @impl true
  def update({:event, %Event.Key{code: "q", kind: "press"}}, state), do: {:stop, state}
  def update({:info, :tick}, state), do: {:noreply, %{state | angle: state.angle + 0.05}}
  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state), do: [Subscription.interval(:spin, 33, :tick)]
end

{:ok, pid} = Viewport3DCube.start_link(name: nil)

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
