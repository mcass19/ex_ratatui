# Vendored crates

This directory contains a copy of the [`ratatui-3d`](https://github.com/limlabs/ratatui-3d)
software 3D renderer, used by the `ExRatatui.Widgets.Viewport3D` widget.

## Provenance

- Source: https://github.com/limlabs/ratatui-3d
- Upstream revision: see `UPSTREAM_REV`
- License: MIT (Copyright the ratatui-3d authors)

Two crates are vendored:

- `render3d/` - the renderer engine (no ratatui dependency)
- `ratatui-3d/` - the ratatui integration layer (`Viewport3DStatic` and the blit modes)

Upstream is git-only (not published to crates.io) and early-stage, so the crates are
vendored in-tree to keep the precompiled NIF self-contained and reproducible, and to allow
local patches.

## Local changes

- `default` features are emptied in both `Cargo.toml` files. The `obj`, `gltf`, and `gpu`
  features stay available but off: model loading and material textures are out of scope,
  and the `wgpu` GPU pipeline is unsafe to initialize inside a NIF.
- `ratatui-3d` pulls `render3d` with `default-features = false`.
- `ratatui-3d`'s upstream `[dev-dependencies]` and `[[example]]` targets are dropped; the
  upstream `examples/` and `assets/` directories and the `render3d-node` crate are not
  vendored.

## Updating

Re-copy `crates/render3d` and `crates/ratatui-3d` from upstream, reapply the local changes
above, and update `UPSTREAM_REV`.
