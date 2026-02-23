# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **BREAKING**: Terminal state is now per-process via Rust ResourceArc instead of a global mutex
  - `ExRatatui.run/1` closure now receives the terminal reference (1-arity)
  - `ExRatatui.draw/1` is now `ExRatatui.draw/2` (terminal reference as first argument)
  - `ExRatatui.init_test_terminal/2` returns a terminal reference instead of `:ok`
  - `ExRatatui.get_buffer_content/0` is now `ExRatatui.get_buffer_content/1`
  - `ExRatatui.App` behaviour users: **no API changes**
- Terminal is automatically restored when the terminal reference is garbage collected (crash safety)
- Test terminal instances are now independent, enabling `async: true` for rendering tests

## [0.3.0] - 2026-02-23

### Added

- Typespecs (`@type t`) for all widget, event, and frame structs
- Function specs (`@spec`) for all public API functions
- Dialyzer static analysis in CI

### Changed

- Extracted `Event.Key`, `Event.Mouse`, `Event.Resize` and `Layout.Rect` into their own files

### Fixed

- Server `start_link/1` now supports `name: nil` to start without process registration
- App-based TUI processes hanging on macOS — the event poll loop now delegates the timeout to the NIF on the DirtyIo scheduler instead of using `Process.send_after/3`, which was causing the GenServer to stop processing messages

## [0.2.0] - 2026-02-21

### Changed

- Simplified release workflow by using `rustler-precompiled-action` instead of manual build and packaging steps

### Added

- Precompiled NIF target for `riscv64gc-unknown-linux-gnu` (Nerves RISC-V boards)
- System monitor example (`examples/system_monitor.exs`) for running on Nerves devices via SSH

## [0.1.1] - 2026-02-19

### Changed

- Improved HexDocs module grouping: Frame moved under Layout, App under new Application group
- Added demo GIF to README

### Fixed

- Changelog formatting for ex_doc compatibility

## [0.1.0] - 2026-02-19

### Added

- **Widgets:** Paragraph (with alignment, wrapping, scrolling), Block (borders, titles, padding), List (selectable with highlight), Table (headers, rows, column constraints), and Gauge (progress bar)
- **Layout engine:** Constraint-based area splitting via `ExRatatui.Layout.split/3` with support for `:percentage`, `:length`, `:min`, `:max`, and `:ratio` constraints
- **Event polling:** Non-blocking keyboard, mouse, and resize event handling on BEAM's DirtyIo scheduler
- **Styling system:** Named colors, RGB (`{:rgb, r, g, b}`), 256-color indexed (`{:indexed, n}`), and text modifiers (bold, italic, underlined, dim, crossed out, etc.)
- **Terminal lifecycle:** `ExRatatui.run/1` for automatic terminal init and cleanup
- **OTP App behaviour:** `ExRatatui.App` with LiveView-inspired callbacks (`mount/1`, `render/2`, `handle_event/2`, `handle_info/2`) for building supervised TUI applications
- **GenServer runtime:** manages terminal lifecycle, self-scheduling event polling, and callback dispatch under OTP supervision
- **Frame struct:** `ExRatatui.Frame` carries terminal dimensions to `render/2` callbacks
- **Test backend:** Headless `TestBackend` via `init_test_terminal/2` and `get_buffer_content/0` for CI-friendly rendering verification
- **Precompiled NIFs:** Via `rustler_precompiled` for Linux, macOS, and Windows (x86_64 and aarch64) — no Rust toolchain required
- **Examples:** `hello_world.exs` (minimal display), `counter.exs` (interactive key events), `counter_app.exs` (App-based counter), `task_manager.exs` (full app with all widgets), and `examples/task_manager/` (supervised Ecto + SQLite CRUD app)

[Unreleased]: https://github.com/mcass19/ex_ratatui/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/mcass19/ex_ratatui/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mcass19/ex_ratatui/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/mcass19/ex_ratatui/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mcass19/ex_ratatui/releases/tag/v0.1.0
