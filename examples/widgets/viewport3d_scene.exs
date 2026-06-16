# Example: Viewport3D — a multi-object scene (cube, sphere, plane wall) lit by all
# three light types, with the camera slowly orbiting the origin.
# Run with: mix run examples/widgets/viewport3d_scene.exs
#
# Controls:
#   m = cycle render mode (auto / kitty / sixel / iterm2 / half_block / braille / ascii)
#   q = quit
#
# Requires a true-color terminal. `probe_image_protocol: true` runs the terminal
# capability probe after init, so the default `:auto` mode renders crisp pixel
# graphics scaled to the pane on capable terminals (Ghostty/WezTerm/Kitty) and
# falls back to braille elsewhere.

defmodule Viewport3DScene do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene, Transform}
  alias ExRatatui.Widgets.{Block, Paragraph, Viewport3D}

  @modes [:auto, :kitty, :sixel, :iterm2, :half_block, :braille, :ascii]

  @impl true
  def init(_opts),
    do:
      {:ok,
       %{camera: %Camera{position: {4.0, 3.0, 5.0}, target: {0.0, 0.0, 0.0}}, render_mode: :auto},
       probe_image_protocol: true}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [scene_area, help_area] = Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])

    objects = [
      %Object{
        mesh: Mesh.cube(),
        material: %Material{color: {100, 150, 255}},
        transform: %Transform{position: {-1.4, 0.0, 0.0}}
      },
      %Object{
        mesh: Mesh.sphere(20, 28),
        material: %Material{color: {255, 110, 110}},
        transform: %Transform{position: {1.4, 0.0, 0.0}}
      },
      # The plane's front face is its -Y side; rotate it to stand up as a wall
      # facing the camera, scaled into a backdrop.
      %Object{
        mesh: Mesh.plane(),
        material: %Material{color: {40, 44, 52}},
        transform: %Transform{
          position: {0.0, 0.0, -2.0},
          rotation: {:axis_angle, {1.0, 0.0, 0.0}, -:math.pi() / 2},
          scale: {8.0, 1.0, 5.0}
        }
      }
    ]

    viewport = %Viewport3D{
      scene: %Scene{
        objects: objects,
        lights: [
          Light.ambient({255, 255, 255}, 0.12),
          Light.directional({-1.0, -1.0, -0.5}, {180, 200, 255}),
          Light.point({2.0, 2.5, 2.5}, {255, 220, 180})
        ],
        background: {6, 8, 14}
      },
      camera: state.camera,
      render_mode: state.render_mode,
      block: %Block{
        title: " Viewport3D — scene (cube, sphere, plane)   mode: #{state.render_mode} ",
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

  def update({:info, :tick}, state),
    do: {:noreply, %{state | camera: Camera.orbit(state.camera, 0.02, 0.0)}}

  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state), do: [Subscription.interval(:orbit, 33, :tick)]

  defp next_mode(mode) do
    index = Enum.find_index(@modes, &(&1 == mode))
    Enum.at(@modes, rem(index + 1, length(@modes)))
  end
end

{:ok, pid} = Viewport3DScene.start_link(name: nil)

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
