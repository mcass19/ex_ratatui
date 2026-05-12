# Example: render an image through CellSession and dump the cell grid.
#
# `CellSession` lets you produce image output without a terminal — perfect
# for Livebook / Kino integrations, snapshot tests, or any context where
# you need cells as plain data. Since CellSession can only carry cells
# (not escape sequences), images always render via halfblocks here,
# regardless of any :protocol opt set at construction.
#
# Run with: mix run examples/headless_image.exs
#
# Image source mirrors examples/image_demo.exs:
#   - IMAGE_PATH env var, or
#   - https://picsum.photos/200/100, or
#   - a 1x1 magenta fallback

alias ExRatatui.CellSession
alias ExRatatui.CellSession.Snapshot
alias ExRatatui.Image
alias ExRatatui.Layout.Rect

defmodule HeadlessImage do
  def load_bytes do
    case System.get_env("IMAGE_PATH") do
      nil -> fetch_or_fallback()
      path -> File.read!(path)
    end
  end

  defp fetch_or_fallback do
    case fetch("https://picsum.photos/200/100") do
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
end

# Build the image — protocol/resize selection happens here. CellSession
# will override the protocol to halfblocks at render time, but resize is
# honored.
bytes = HeadlessImage.load_bytes()
{:ok, image} = Image.new(bytes, resize: :fit)

# 40 columns × 20 rows leaves enough vertical resolution for halfblocks
# to give a recognizable preview of the source image.
session = CellSession.new(40, 20)
:ok = CellSession.draw(session, [{image, %Rect{x: 0, y: 0, width: 40, height: 20}}])

%Snapshot{width: w, cells: cells} = CellSession.take_cells(session)
:ok = CellSession.close(session)

IO.puts("Rendered #{byte_size(bytes)} bytes of image into #{w}×#{div(length(cells), w)} cells:\n")

cells
|> Enum.chunk_every(w)
|> Enum.each(fn row ->
  row |> Enum.map_join(& &1.symbol) |> IO.puts()
end)

IO.puts(
  "\nSame model code in a real Kitty/Ghostty terminal would render via the Kitty graphics protocol."
)
