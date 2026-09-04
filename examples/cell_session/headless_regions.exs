# Example: render a 3D scene and an image to real pixels through a CellSession.
#
# A CellSession created with `font_size:` knows how big its cells are in
# pixels, so pixel-mode widgets (Viewport3D, Image) hand over RGB bitmaps
# instead of half-block cells. This is the path an e-ink badge or a canvas
# renderer takes: paint the cells, then blit each region over its rect.
# Every frame carries the complete list of regions on screen — here two,
# one per widget.
#
# Writes each region as a binary PPM (`P6`) next to a text dump of the cell
# grid, so the results can be opened in any image viewer:
#
#   mix run examples/cell_session/headless_regions.exs
#   mix run examples/cell_session/headless_regions.exs /tmp/regions
#
# The image comes from IMAGE_PATH, else https://picsum.photos/200/150, else
# an embedded 1x1 PNG. No terminal is touched; safe to run anywhere.

alias ExRatatui.CellSession
alias ExRatatui.CellSession.{Diff, Region}
alias ExRatatui.Image
alias ExRatatui.Layout.Rect
alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Object, Scene}
alias ExRatatui.Widgets.{Block, Viewport3D}

defmodule HeadlessRegions do
  def load_image_bytes do
    case System.get_env("IMAGE_PATH") do
      nil -> fetch_or_fallback()
      path -> File.read!(path)
    end
  end

  defp fetch_or_fallback do
    case fetch("https://picsum.photos/200/150") do
      {:ok, bytes} -> bytes
      _ -> fallback_png()
    end
  end

  defp fetch(url) do
    :inets.start()
    :ssl.start()

    case :httpc.request(
           :get,
           {String.to_charlist(url), []},
           [{:timeout, 5_000}],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _, body}} when status in 200..299 -> {:ok, body}
      other -> {:error, other}
    end
  rescue
    _ -> {:error, :exception}
  end

  defp fallback_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
    )
  end

  def write_ppm(path, %Region{} = region) do
    File.write!(
      path,
      "P6\n#{region.pixel_width} #{region.pixel_height}\n255\n" <> region.data
    )
  end
end

out_prefix = List.first(System.argv()) || Path.join(System.tmp_dir!(), "ex_ratatui_regions")

# A 60x20 cell surface whose cells are 8x16 pixels: 480x320 pixels total.
{cols, rows, font_size} = {60, 20, {8, 16}}
session = CellSession.new(cols, rows, font_size: font_size)

scene = %Scene{
  objects: [
    %Object{
      mesh: Mesh.cube(),
      material: %Material{color: {120, 170, 255}},
      transform: %ExRatatui.ThreeD.Transform{rotation: {:euler_xyz, {0.5, 0.8, 0.0}}}
    }
  ],
  lights: [
    Light.ambient({255, 255, 255}, 0.2),
    Light.directional({-1.0, -1.0, -1.0}, {255, 255, 255})
  ],
  background: {255, 255, 255}
}

viewport = %Viewport3D{
  scene: scene,
  camera: %Camera{position: {2.5, 2.0, 3.5}, target: {0.0, 0.0, 0.0}},
  render_mode: :auto,
  block: %Block{borders: [:all], title: " cube "}
}

# :scale fills the pane; the background paints whatever the picture leaves.
{:ok, picture} =
  Image.new(HeadlessRegions.load_image_bytes(), resize: :scale, background: {255, 255, 255})

left = %Rect{x: 0, y: 0, width: 30, height: rows}
right = %Rect{x: 30, y: 0, width: 30, height: rows}

:ok = CellSession.draw(session, [{viewport, left}, {picture, right}])
%Diff{ops: ops, regions: regions} = CellSession.take_cells_diff(session)
:ok = CellSession.close(session)

# The block border is ordinary cells; both regions cover blank cells.
ops
|> Enum.group_by(& &1.row)
|> Enum.sort()
|> Enum.each(fn {_row, cells} ->
  cells |> Enum.sort_by(& &1.col) |> Enum.map_join(& &1.symbol) |> IO.puts()
end)

IO.puts("")

regions
|> Enum.with_index()
|> Enum.each(fn {%Region{} = region, index} ->
  path = "#{out_prefix}_#{index}.ppm"
  HeadlessRegions.write_ppm(path, region)

  IO.puts(
    "region #{index}: #{region.width}x#{region.height} cells at (#{region.x}, #{region.y}), " <>
      "#{region.pixel_width}x#{region.pixel_height} px, #{byte_size(region.data)} bytes of " <>
      "#{region.format} -> #{path}"
  )
end)
