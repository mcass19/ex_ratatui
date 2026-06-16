# Example: Viewport3D — drive the camera and switch render modes / pipelines live.
# Run with: mix run examples/widgets/viewport3d_controls.exs
#
# Controls:
#   arrows  = orbit the camera
#   i / o   = zoom in / out
#   m       = cycle render mode (auto / kitty / sixel / iterm2 / half_block / braille / ascii)
#   p       = toggle pipeline (rasterize / raytrace)
#   q       = quit
#
# Pixel modes (auto/kitty/sixel/iterm2) render crisp graphics scaled to the pane
# on capable terminals (Ghostty/WezTerm/Kitty) and fall back to braille elsewhere.
# `probe_image_protocol: true` runs the terminal capability probe after mount so
# the default `:auto` mode resolves to the detected protocol.
#
# Requires a true-color terminal. Camera movement is pure: each key event maps
# to ExRatatui.ThreeD.Camera.orbit/3 or zoom/2 and stores the new camera.

defmodule Viewport3DControls do
  use ExRatatui.App

  alias ExRatatui.{Event, Layout, Layout.Rect, Style}
  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene}
  alias ExRatatui.Widgets.{Block, Paragraph, Viewport3D}

  @modes [:auto, :kitty, :sixel, :iterm2, :half_block, :braille, :ascii]

  @impl true
  def mount(_opts) do
    {:ok,
     %{
       camera: %Camera{position: {3.0, 2.5, 4.0}, target: {0.0, 0.0, 0.0}},
       render_mode: :auto,
       pipeline: :rasterize
     }, probe_image_protocol: true}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
    [scene_area, help_area] = Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])

    scene = %Scene{
      objects: [
        %Object{mesh: Mesh.cube(), material: %Material{color: {120, 200, 160}}}
      ],
      lights: [
        Light.ambient({255, 255, 255}, 0.15),
        Light.directional({-1.0, -1.0, -1.0}, {255, 255, 255}),
        Light.point({2.0, 3.0, 2.0}, {255, 220, 180})
      ],
      background: {8, 8, 16}
    }

    viewport = %Viewport3D{
      scene: scene,
      camera: state.camera,
      render_mode: state.render_mode,
      pipeline: state.pipeline,
      block: %Block{
        title: " mode: #{state.render_mode}   pipeline: #{state.pipeline} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    help = %Paragraph{
      text: "  arrows = orbit   i/o = zoom   m = mode   p = pipeline   q = quit",
      style: %Style{fg: :dark_gray}
    }

    [{viewport, scene_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: "left", kind: "press"}, state),
    do: {:noreply, orbit(state, 0.15, 0.0)}

  def handle_event(%Event.Key{code: "right", kind: "press"}, state),
    do: {:noreply, orbit(state, -0.15, 0.0)}

  def handle_event(%Event.Key{code: "up", kind: "press"}, state),
    do: {:noreply, orbit(state, 0.0, -0.15)}

  def handle_event(%Event.Key{code: "down", kind: "press"}, state),
    do: {:noreply, orbit(state, 0.0, 0.15)}

  def handle_event(%Event.Key{code: "i", kind: "press"}, state),
    do: {:noreply, zoom(state, -0.5)}

  def handle_event(%Event.Key{code: "o", kind: "press"}, state),
    do: {:noreply, zoom(state, 0.5)}

  def handle_event(%Event.Key{code: "m", kind: "press"}, state),
    do: {:noreply, %{state | render_mode: next_mode(state.render_mode)}}

  def handle_event(%Event.Key{code: "p", kind: "press"}, state),
    do: {:noreply, %{state | pipeline: toggle_pipeline(state.pipeline)}}

  def handle_event(_event, state), do: {:noreply, state}

  defp orbit(state, yaw, pitch), do: %{state | camera: Camera.orbit(state.camera, yaw, pitch)}
  defp zoom(state, delta), do: %{state | camera: Camera.zoom(state.camera, delta)}

  defp next_mode(mode) do
    index = Enum.find_index(@modes, &(&1 == mode))
    Enum.at(@modes, rem(index + 1, length(@modes)))
  end

  defp toggle_pipeline(:rasterize), do: :raytrace
  defp toggle_pipeline(:raytrace), do: :rasterize
end

{:ok, pid} = Viewport3DControls.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
