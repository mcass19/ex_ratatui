# Rendering to a framebuffer

An `ExRatatui.App` can run on a display that has no terminal at all, such as the 1-bit e-ink panel on the Goatmire name badge. The app does not change. It renders into an `ExRatatui.CellSession`, and something on the device side turns the cells and pixel regions of every frame into pixels for the panel.

That something is [raster_ex_ratatui](https://github.com/mcass19/raster_ex_ratatui). A surface is one module that describes the panel (its size, its pixel format, how bytes reach it), and the library does the rest: it starts the app, folds every diff, rasterises glyphs and pixel regions, pushes only what changed at a pace the panel tolerates, and forwards input. It also ships helpers for Linux framebuffers and evdev keyboards. Its [Building a Surface](https://hexdocs.pm/raster_ex_ratatui/surfaces.html) guide covers the contract.

On the ex_ratatui side, two pieces make this work, both documented in the [CellSession guide](cell_session.md):

- [Pixel regions](cell_session.md#pixel-regions-for-surfaces-with-real-pixels): a session created with `font_size:` ships `Viewport3D` and `Image` as RGB bitmaps, so they render at the panel's native resolution instead of as half blocks.
- The `{:cell_session, session, writer}` transport, which runs an app on a session and hands every `%CellSession.Diff{}` to the writer.
