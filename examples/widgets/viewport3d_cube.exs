# Example: Viewport3D — a single lit cube spinning in 3D, rasterized into the terminal.
# Run with: mix run examples/widgets/viewport3d_cube.exs
#
# Controls:
#   m = cycle render mode (auto / kitty / sixel / iterm2 / half_block / braille / ascii)
#   q = quit
#
# Requires a true-color terminal. `probe_image_protocol: true` runs the terminal
# capability probe after init, so the default `:auto` mode renders crisp pixel
# graphics scaled to the pane on capable terminals (Ghostty/WezTerm/Kitty) and
# falls back to braille elsewhere. The cube spins every frame, and pixel modes
# re-transmit the image each frame, so `:auto` may flicker on some terminals —
# press `m` for `:braille` to smooth the motion (see the 3D guide).
#
# Uses the reducer runtime: a Subscription.interval advances the rotation angle,
# and render/2 rebuilds the scene each frame from that angle.

defmodule Viewport3DCube do
  use ExRatatui.App, runtime: :reducer

  alias ExRatatui.{Event, Layout, Layout.Rect, Style, Subscription}
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene, Transform}
  alias ExRatatui.Widgets.{Block, Paragraph, Viewport3D}

  @modes [:auto, :kitty, :sixel, :iterm2, :half_block, :braille, :ascii]

  @impl true
  def init(_opts), do: {:ok, %{angle: 0.0, render_mode: :auto}, probe_image_protocol: true}

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
      render_mode: state.render_mode,
      block: %Block{
        title: " Viewport3D — spinning cube   mode: #{state.render_mode} ",
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

  def update({:info, :tick}, state), do: {:noreply, %{state | angle: state.angle + 0.05}}
  def update(_msg, state), do: {:noreply, state}

  @impl true
  def subscriptions(_state), do: [Subscription.interval(:spin, 33, :tick)]

  defp next_mode(mode) do
    index = Enum.find_index(@modes, &(&1 == mode))
    Enum.at(@modes, rem(index + 1, length(@modes)))
  end
end

{:ok, pid} = Viewport3DCube.start_link(name: nil)

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
