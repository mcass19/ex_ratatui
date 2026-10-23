# Rendering to a framebuffer

An `ExRatatui.App` can run on a display that has no terminal at all, such as the 1-bit e-ink panel on the Goatmire name badge. The app does not change. It renders into an `ExRatatui.CellSession`, and something on the device side turns the cells and pixel regions of every frame into pixels for the panel.

That something is [raster_ex_ratatui](https://github.com/mcass19/raster_ex_ratatui). A surface is one module that describes the panel (its size, its pixel format, how bytes reach it), and the library does the rest: it starts the app, folds every diff, rasterises glyphs and pixel regions, pushes only what changed at a pace the panel tolerates, and forwards input. It also ships helpers for Linux framebuffers and evdev keyboards. Its [Building a Surface](https://hexdocs.pm/raster_ex_ratatui/surfaces.html) guide covers the contract.

On the ex_ratatui side, two pieces make this work, both documented in the [CellSession guide](cell_session.md):

- [Pixel regions](cell_session.md#pixel-regions-for-surfaces-with-real-pixels): a session created with `font_size:` ships `Viewport3D` and `Image` as RGB bitmaps, so they render at the panel's native resolution instead of as half blocks.
- The `{:cell_session, session, writer}` transport, which runs an app on a session and hands every `%CellSession.Diff{}` to the writer.

## Panels mounted on their side

A panel is often fixed in the enclosure at a quarter turn from the orientation the app draws in, so the surface turns every frame on its way to the hardware. Cells and glyph blocks are cheap to turn, but a region is not: its bitmap arrives in the app's orientation, and gathering each destination row out of a source column costs about as much again as painting a panel that is the right way up.

`ExRatatui.CellSession.Region.rotate/2` turns the bitmap in Rust instead, in a single pass that walks destination rows so the writes stay sequential. The turned bytes then go through the same flat row-by-row path an upright panel uses. `ExRatatui.Pixels.rotate_rgb8/4` is the same operation on raw bytes and dimensions, for a surface that keeps its own buffers.

Only the pixels move. A region's `x`, `y`, `width` and `height` are the app's cell coordinates, and turning them needs the size of the grid they sit in, which a region does not carry — the surface already knows that size and maps the rect onto its screen itself.

## Packing regions

A region still has to become the panel's bytes: scaled to its rect when the bitmap was capped or the surface scales up, cut where the rect runs off the grid, turned for a panel on its side, and packed into the panel's pixel format. Done per pixel in Elixir that is the most expensive part of a frame.

`ExRatatui.Pixels.pack_rgb8/5` does all of it in one native pass, writing straight into the packed output:

```elixir
{packed, width, height} =
  ExRatatui.Pixels.pack_rgb8(region.data, region.pixel_width, region.pixel_height, :rgb565,
    scale_to: {rect_w, rect_h},   # the rect's full pixel size, in the app's orientation
    clip: {visible_w, visible_h}, # the part of it on screen
    rotate: 90,
    origin: {x, y}                # panel position of the output's top-left pixel
  )
```

`:rgb565` and `:xrgb8888` cover the usual Linux framebuffers, and `:mono_bayer4` dithers to `0`/`255` for 1-bit panels, anchored at `:origin` so the pattern stays put as regions move. A surface with a format of its own asks for `:rgb8` and packs the result itself, still getting the sampling, clipping and rotation natively. Sampling is against the full `:scale_to`, so a clipped region shows the same pixels it would if the whole rect fit. The moduledoc has the exact byte layouts.
