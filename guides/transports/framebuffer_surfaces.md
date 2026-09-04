# Rendering to a framebuffer

An `ExRatatui.App` can run on a display that has no terminal at all: an e-ink badge, a small LCD on a Nerves board, a Linux framebuffer device. The library does not know how to drive any of those panels, and it does not have to. It renders every frame into a `CellSession`, and a small adapter on the device side turns that into pixels. This guide explains what that adapter is, walks through the one that ships on the Goatmire name badge, and shows what changes for a colour panel.

The [CellSession guide](cell_session.md) documents the session API itself; this guide is about what to build on top of it.

## The mental model

Three layers, and only the last one is device-specific:

1. **The app** renders widgets, exactly as it would in a terminal. It does not know where it is running.
2. **The session** is where ratatui draws. Instead of ANSI bytes it keeps a grid of *cells*: one character, a foreground colour, a background colour, and modifiers per position. Each frame the runtime hands the consumer a `%CellSession.Diff{}` with the cells that changed since the previous frame. When the session was created with a `font_size:`, the diff also carries `regions`: ready-made RGB bitmaps for the `Viewport3D` and `Image` widgets, each with the rectangle of cells it covers.
3. **The adapter** turns cells and regions into a pixel buffer and pushes it to the panel driver. It also turns buttons or touches into key events for the app.

Everything above the adapter is shared with every other transport. A `Viewport3D` that renders through Kitty graphics in a terminal renders as a pixel region on the panel from the same code.

## What the adapter has to do

Four pieces, in the order the data flows:

**Choose a bitmap font and size the grid.** Every character becomes a fixed block of pixels, for example 6×8 or 8×16. The panel resolution divided by that block is the cell grid: a 400×300 panel at 6×8 gives 66 columns by 37 rows, with a few pixels of margin left over. Create the session at that size and tell it the block size:

```elixir
session = ExRatatui.CellSession.new(66, 37, font_size: {6, 8})
```

**Keep the current frame.** Hold a map from `{col, row}` to the last cell seen there and apply every diff's ops to it. Keep the region list from the latest payload as it is: it is the complete set of regions on screen for that frame, not a delta, so it replaces the previous list outright.

**Rasterise.** For every cell, stamp the glyph's pixels in the foreground colour and fill the rest of the block with the background colour, at pixel position `{col * font_width, row * font_height}`. Then copy every region's bitmap over its rectangle, at `{region.x * font_width, region.y * font_height}`, scaling up if the bitmap is smaller than the rectangle (which only happens when a very large rectangle hit the library's size cap). Cells first, regions second: the covered cells arrive blank, so the order just means "background, then picture".

**Push and listen.** Write the pixel buffer to the panel, on whatever schedule the panel tolerates, and feed input back to the app by sending the runtime server `{:ex_ratatui_event, %ExRatatui.Event.Key{...}}` messages, exactly as a terminal transport would.

Wiring it to the runtime is the standard cell-session transport: the writer function receives every diff.

```elixir
writer = fn %ExRatatui.CellSession.Diff{} = diff -> send(adapter_pid, {:frame, diff}) end

{:ok, server} =
  ExRatatui.Transport.start_server(
    mod: MyApp.TUI,
    transport: {:cell_session, session, writer}
  )
```

## Worked example: the name badge

The [Goatmire name badge](https://github.com/protolux-electronics/name_badge) is a Nerves device with a 400×300 1-bit e-ink panel driven over SPI. Its adapter is three modules, and they map one to one onto the pieces above:

- `NameBadge.ExRatatui.Font` is the bitmap font: a hand-drawn 6×8 set for ASCII, box drawing and blocks, plus the braille block, eighth blocks and quadrants generated from their Unicode bit layouts at compile time, so `Canvas` and `BigText` glyphs render too.
- `NameBadge.Screen.ExRatatui` is the transport glue: it creates the session with the font's cell size, starts the runtime server with a writer that sends diffs back to the screen process, maps the badge's two buttons to key events, and hands the finished bitmap to the display driver.
- `NameBadge.ExRatatui.Raster` is the rasteriser: it keeps the cell map and the region list, stamps glyphs, blits regions, and produces the 400×300 buffer the panel driver packs to 1 bit per pixel.

The badge has one problem a colour panel does not: it cannot show colour or grey. So the raster collapses every colour to a *tone*. Named colours keep their terminal meaning (`:black` is ink, everything else on a plain background is ink on paper, `:reversed` inverts the cell), RGB colours are thresholded on luminance, and region pixels go through a Bayer ordered dither so a shaded 3D render still reads as light and dark faces. That tone logic is the badge's own, and it is the part a colour panel throws away.

Frame rate on the badge is set by the panel, not the library: one full-frame SPI write takes about a second, and the robot screen refreshes once per second on purpose. The runtime produces a diff per render regardless; the adapter decides when to push.

## What changes for a colour panel

A reTerminal, a PiTFT, or any Linux framebuffer device is the same adapter with the hard part removed:

- **Colours map directly.** Foreground and background become RGB, with `:reset` mapped to whatever theme colours the surface wants for text and background. Named ANSI colours need a small palette table; `{:rgb, r, g, b}` and `{:indexed, n}` map like a terminal would.
- **Regions are copied as they are.** No dithering, no thresholding: the bitmap is already RGB8, row-major, three bytes per pixel.
- **The last step is a framebuffer write.** Open the device, pack pixels to the panel's format, and write the buffer:

```elixir
# RGB565 (typical for small SPI TFTs): 5 bits red, 6 green, 5 blue.
defp rgb565(r, g, b) do
  <<(r >>> 3)::5, (g >>> 2)::6, (b >>> 3)::5>>
end

{:ok, fb} = File.open("/dev/fb0", [:write, :binary, :raw])
:ok = :file.pwrite(fb, 0, packed_frame)
```

The panel's pixel format, stride, and orientation come from the framebuffer's screen info (`fbset` on the device prints them); RGB565 little-endian is the common case for small displays, 32-bit XRGB for HDMI-class outputs. On a panel that refreshes at video rates the adapter can write a full frame per diff; on a slow SPI panel, batch or throttle as the badge does.

Everything else is identical: the font, the cell map, the region list, the stamping and blitting loop. Starting from the badge's `Raster`, the work is replacing the tone functions with colour lookups and the 1-bit pack with the framebuffer pack.

## Checklist for a new surface

- A bitmap font at a fixed cell size, covering at least ASCII, box drawing, blocks, and braille if the app uses `Canvas`.
- Grid size: panel pixels divided by the cell size, session created with `font_size:`.
- A cell map fed by diffs and a region list replaced per frame.
- A rasteriser: glyphs with foreground over background, then regions blitted over their rectangles.
- A palette for the surface: what `:reset` and the named colours mean there.
- A frame push that respects the panel's refresh cost.
- Input: buttons or touch turned into `%ExRatatui.Event.Key{}` messages sent to the server.

With those in place, every widget in the library renders on the panel, and `Viewport3D` and `Image` render at the panel's native resolution.
