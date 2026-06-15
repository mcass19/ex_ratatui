# Example: Viewport3D — an articulated two-segment arm built from a scene-graph
# (`ExRatatui.ThreeD.Node`) and flattened to a flat scene each frame. The base
# rotates and the elbow swings, showing forward kinematics composed via
# `Transform.compose/2`.
# Run with: mix run examples/widgets/viewport3d_articulated.exs
#
# Controls: q = quit
#
# Requires a true-color terminal.

defmodule Viewport3DArticulated do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Node, Object, Transform}
  alias ExRatatui.Widgets.{Block, Paragraph, Viewport3D}

  @impl true
  def init(_opts),
    do: {:ok, %{t: 0.0, camera: %Camera{position: {2.2, 1.8, 2.6}, target: {0.0, 0.6, 0.0}}}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [scene_area, help_area] = Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])

    base_angle = state.t
    elbow_angle = :math.sin(state.t * 1.7) * 0.9

    # A base cylinder; a forearm box pivoting at the top of the base; a hand
    # box pivoting at the elbow. Joints carry rotation+translation only; the
    # visual boxes/cylinder carry the scale.
    arm = %Node{
      transform: %Transform{rotation: {:axis_angle, {0.0, 1.0, 0.0}, base_angle}},
      visual: %Object{
        mesh: Mesh.cylinder(24),
        material: %Material{color: {120, 124, 135}},
        transform: %Transform{position: {0.0, 0.15, 0.0}, scale: {0.5, 0.3, 0.5}}
      },
      children: [
        %Node{
          transform: %Transform{
            position: {0.0, 0.3, 0.0},
            rotation: {:axis_angle, {0.0, 0.0, 1.0}, elbow_angle}
          },
          visual: %Object{
            mesh: Mesh.cube(),
            material: %Material{color: {210, 90, 80}},
            transform: %Transform{position: {0.0, 0.45, 0.0}, scale: {0.18, 0.9, 0.18}}
          },
          children: [
            %Node{
              transform: %Transform{
                position: {0.0, 0.9, 0.0},
                rotation: {:axis_angle, {0.0, 0.0, 1.0}, elbow_angle}
              },
              visual: %Object{
                mesh: Mesh.cube(),
                material: %Material{color: {90, 170, 220}},
                transform: %Transform{position: {0.0, 0.25, 0.0}, scale: {0.24, 0.5, 0.24}}
              }
            }
          ]
        }
      ]
    }

    scene =
      Node.to_scene(arm,
        lights: [
          Light.ambient({255, 255, 255}, 0.25),
          Light.directional({1.0, 1.0, 1.0}, {255, 255, 255}),
          Light.directional({-1.0, 1.0, -1.0}, {150, 170, 210}, intensity: 0.5)
        ],
        background: {10, 12, 18}
      )

    viewport = %Viewport3D{
      scene: scene,
      camera: state.camera,
      render_mode: :half_block,
      block: %Block{
        title: " Viewport3D — articulated arm (scene-graph) ",
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

  def update({:info, :tick}, state) do
    {:noreply, %{state | t: state.t + 0.04, camera: Camera.orbit(state.camera, 0.01, 0.0)}}
  end

  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state), do: [Subscription.interval(:tick, 33, :tick)]
end

{:ok, pid} = Viewport3DArticulated.start_link(name: nil)

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
