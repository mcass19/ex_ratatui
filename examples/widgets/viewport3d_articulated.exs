# Example: Viewport3D — an articulated two-segment arm built from a scene-graph
# (`ExRatatui.ThreeD.Node`) and flattened to a flat scene each frame. The base
# rotates and the elbow swings, showing forward kinematics composed via
# `Transform.compose/2`.
# Run with: mix run examples/widgets/viewport3d_articulated.exs
#
# Controls:
#   m = cycle render mode (auto / kitty / sixel / iterm2 / half_block / braille / ascii)
#   q = quit
#
# Requires a true-color terminal. `probe_image_protocol: true` runs the terminal
# capability probe after init, so the default `:auto` mode renders crisp pixel
# graphics scaled to the pane on capable terminals (Ghostty/WezTerm/Kitty) and
# falls back to braille elsewhere. The arm animates every frame, and pixel modes
# re-transmit the image each frame, so `:auto` may flicker on some terminals —
# press `m` for `:braille` to smooth the motion (see the 3D guide).

defmodule Viewport3DArticulated do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Node, Object, Transform}
  alias ExRatatui.Widgets.{Block, Paragraph, Viewport3D}

  @modes [:auto, :kitty, :sixel, :iterm2, :half_block, :braille, :ascii]

  @impl true
  def init(_opts),
    do:
      {:ok,
       %{
         t: 0.0,
         camera: %Camera{position: {2.2, 1.8, 2.6}, target: {0.0, 0.6, 0.0}},
         render_mode: :auto
       }, probe_image_protocol: true}

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
      render_mode: state.render_mode,
      block: %Block{
        title: " Viewport3D — articulated arm (scene-graph)   mode: #{state.render_mode} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    help = %Paragraph{text: "  m = mode   q = quit", style: %Style{fg: :dark_gray}}
    [{viewport, scene_area}, {help, help_area}]
  end

  @impl true
  def update({:event, %Event.Key{code: "q", kind: "press"}}, state), do: {:stop, state}

  def update({:event, %Event.Key{code: "m", kind: "press"}}, state),
    do: {:noreply, %{state | render_mode: next_mode(state.render_mode)}}

  def update({:info, :tick}, state) do
    {:noreply, %{state | t: state.t + 0.04, camera: Camera.orbit(state.camera, 0.01, 0.0)}}
  end

  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state), do: [Subscription.interval(:tick, 33, :tick)]

  defp next_mode(mode) do
    index = Enum.find_index(@modes, &(&1 == mode))
    Enum.at(@modes, rem(index + 1, length(@modes)))
  end
end

{:ok, pid} = Viewport3DArticulated.start_link(name: nil)

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
