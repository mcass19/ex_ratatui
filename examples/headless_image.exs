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

# Halfblocks rendering encodes the image entirely in the fg/bg colors of
# each cell (the symbol is just a ▀ / ▄ / █ block selector). Naively
# printing only `cell.symbol` throws that visual information away and
# produces a high-contrast outline that doesn't look like the source.
# Emit each cell with ANSI fg + bg escapes so a color-capable terminal
# (Ghostty, Kitty, WezTerm, iTerm2, modern xterm, …) actually paints
# the photo.
ansi_color = fn channel, color ->
  base_fg = if channel == :fg, do: 30, else: 40
  bright_fg = if channel == :fg, do: 90, else: 100
  param_fg = if channel == :fg, do: 38, else: 48

  case color do
    nil -> ""
    :reset -> "\e[#{if channel == :fg, do: 39, else: 49}m"
    :black -> "\e[#{base_fg + 0}m"
    :red -> "\e[#{base_fg + 1}m"
    :green -> "\e[#{base_fg + 2}m"
    :yellow -> "\e[#{base_fg + 3}m"
    :blue -> "\e[#{base_fg + 4}m"
    :magenta -> "\e[#{base_fg + 5}m"
    :cyan -> "\e[#{base_fg + 6}m"
    :gray -> "\e[#{base_fg + 7}m"
    :dark_gray -> "\e[#{bright_fg + 0}m"
    :light_red -> "\e[#{bright_fg + 1}m"
    :light_green -> "\e[#{bright_fg + 2}m"
    :light_yellow -> "\e[#{bright_fg + 3}m"
    :light_blue -> "\e[#{bright_fg + 4}m"
    :light_magenta -> "\e[#{bright_fg + 5}m"
    :light_cyan -> "\e[#{bright_fg + 6}m"
    :white -> "\e[#{bright_fg + 7}m"
    {:indexed, n} -> "\e[#{param_fg};5;#{n}m"
    {:rgb, r, g, b} -> "\e[#{param_fg};2;#{r};#{g};#{b}m"
  end
end

cells
|> Enum.chunk_every(w)
|> Enum.each(fn row ->
  row
  |> Enum.map_join(fn cell ->
    ansi_color.(:fg, cell.fg) <> ansi_color.(:bg, cell.bg) <> cell.symbol
  end)
  # Reset at the end of each row so subsequent terminal output isn't
  # accidentally inked in the last cell's bg color.
  |> Kernel.<>("\e[0m")
  |> IO.puts()
end)

IO.puts(
  "\nSame model code in a real Kitty/Ghostty terminal would render via the Kitty graphics protocol."
)
