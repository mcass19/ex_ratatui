# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Reducer runtime** for `ExRatatui.App` via `use ExRatatui.App, runtime: :reducer`. Reducer apps implement `init/1`, `render/2`, and `update/2`, receive terminal input as `{:event, event}`, mailbox messages as `{:info, msg}`, and can declare subscriptions with `subscriptions/1`
- `ExRatatui.Command` — reducer side-effect helpers for immediate messages, delayed messages, async work, and batched command execution
- `ExRatatui.Subscription` — reducer timer/subscription helpers for interval and one-shot self-messages reconciled by stable `id`
- `ExRatatui.Runtime` — runtime inspection helpers exposing snapshots, trace events, and trace enable/disable controls for supervised TUI processes
- `ExRatatui.Runtime.inject_event/2` — deterministic synthetic event injection for supervised apps under `test_mode`
- Example: `examples/reducer_counter_app.exs` — simple reducer-driven counter showing `update/2` and `subscriptions/1`
- **Distribution-attach transport** — serve any `ExRatatui.App` to remote BEAM nodes over Erlang distribution. New `transport: :distributed` option on `ExRatatui.App` and a standalone `ExRatatui.Distributed.Listener` for direct supervision-tree use. Each attaching node gets its own isolated TUI session; widget lists travel as plain BEAM terms with zero NIF on the app node
- `ExRatatui.Distributed` — main API module with `attach/3` for connecting to a remote TUI
- `ExRatatui.Distributed.Listener` — supervisor wrapping a `DynamicSupervisor` for per-attach sessions, with config stored in `:persistent_term`
- Distributed.Client (internal) — local rendering proxy that takes over the terminal, polls events, and forwards them to the remote server
- Server (internal) learns a `transport: {:distributed_server, client_pid, width, height}` init path that sends `{:ex_ratatui_draw, widgets}` over distribution instead of rendering locally
- Guide: `guides/distributed_transport.md` — architecture, quick start, options reference, testing, troubleshooting
- README "Running over Erlang Distribution" section
- `examples/system_monitor.exs` now supports `--distributed` flag for running over Erlang distribution
- `:peer`-based integration tests for the full cross-node roundtrip (tagged `:distributed`, run with `elixir --sname test -S mix test --only distributed`)

### Changed

- `ExRatatui.App` now supports two runtime styles: the existing callback runtime and the new reducer runtime selected with `runtime: :reducer`
- `ExRatatui.Server` now supports reducer runtime options for commands, render suppression, trace state, runtime snapshots, async command tracking, and subscription reconciliation
- `test_mode` now means fully headless local runtime behaviour: it disables live terminal input polling on both `ExRatatui.Server` and `Distributed.Client`, and runtime snapshots expose whether polling is enabled
- Render-command encoding moved into `ExRatatui.Bridge`, making `ExRatatui.draw/2` and `ExRatatui.Session.draw/2` share one validation and encoding path
- Native render-command decoding was refactored into reusable helpers in `native/ex_ratatui/src/decode.rs` and shared between local terminal rendering and session rendering
- ExRatatui.Server event and resize handlers are now shared between `:ssh` and `:distributed_server` transports
- `ExRatatui.App` `dispatch_start/1` routes `:distributed` to `ExRatatui.Distributed.Listener.start_link/1`
- **`WidgetList` `scroll_offset` is now row-based** — previously `scroll_offset` skipped whole items by index; it now skips rows of content. To scroll to a specific item, sum the heights of all preceding items. Items partially above the viewport are clipped at the row level, enabling smooth pixel-row scrolling for chat histories and similar variable-height lists. This is a **breaking change** for callers that relied on the item-index interpretation

### Fixed

- New subscriptions now store their timer reference correctly instead of keeping the `{timer_ref, token}` tuple in the `timer_ref` field, which broke timer cancellation/rearming paths in the reducer runtime
- Async command mappers are now wrapped the same way as async functions, so mapper exceptions/exits return structured error tuples and `active_async_commands` bookkeeping is always decremented
- `ExRatatui.App.mount/1`'s published callback contract now includes the supported `{:ok, state, callback_opts}` form, which keeps reducer-style startup shims aligned with Dialyzer and the runtime's actual behavior
- Invalid reducer/runtime payloads and malformed render commands now fail earlier with clearer Elixir-side or Rust-side validation errors
- **`WidgetList` partial-item clipping** — items straddling the top edge of the viewport are now correctly rendered via an off-screen buffer blit instead of being skipped entirely
- **Parallel cold compile crash** — `ExRatatui.Native` no longer loads its NIF via `@on_load` during dependency compilation. Precompiled/source artifacts are still prepared at compile time, but the NIF now loads lazily on first use, which stops isolated compiler VMs from crashing under parallel cold compiles on this host
- **`test_mode` input flake** — local supervised apps and distributed attach clients no longer poll the real terminal while running headless tests, which removes ambient crossterm events from async test runs and stops spurious renders like the `render?: false` reducer flake
- **SSH `auto_host_key` bootstrap** — host-key generation now recreates the parent `<priv_dir>/ssh/` directory immediately before writing the key, so first boot succeeds even if the app's priv tree was absent or cleaned between runs
### Docs

- README now documents the reducer runtime, reducer example app, command/subscription helpers, and runtime inspection API
- README and `ExRatatui.App` docs now call out that `mount/1` may return runtime opts and that `WidgetList.scroll_offset` is row-based with partial clipping semantics
- Expanded public moduledocs for `ExRatatui.App`, `ExRatatui.Command`, `ExRatatui.Subscription`, and `ExRatatui.Runtime`
- HexDocs module grouping now includes reducer-runtime modules
- README now notes that the native library loads lazily on first use

### Tests

- Added reducer runtime coverage for commands, subscriptions, tracing, render suppression, async failure handling, and invalid runtime return values
- Added coverage for public `Command`, `Subscription`, `Runtime`, `App`, and shared bridge validation paths
- Elixir test coverage remains at 100%

## [0.6.2] - 2026-04-12

## [0.6.1] - 2026-04-09

### Fixed

- **SSH subsystem dispatch** — `ssh host -s Elixir.MyApp.TUI` (and `ExRatatui.SSH.subsystem/1` under `nerves_ssh`) would hang forever instead of rendering. The channel handler was waiting for a `{:ssh_cm, _, {:subsystem, ...}}` message inside `handle_ssh_msg/2`, but OTP `:ssh` consumes that request internally when it matches a name in the daemon's `:subsystems` config — the handler only ever receives `{:ssh_channel_up, ...}`. `ExRatatui.SSH` now detects subsystem-mode dispatch (via a new `subsystem: true` flag baked into the init args by `subsystem/1` and `ExRatatui.SSH.Daemon`) and synthesizes a default 80x24 session + starts the TUI server directly from `{:ssh_channel_up, ...}`. Shell-mode startup (via `ssh_cli`) is unchanged — it still waits for `pty_req` + `shell_req` as before
- **SSH subsystem + `-t` pty_req races** — when a client connects with `ssh -t -s Elixir.MyApp.TUI`, OTP fires `ssh_channel_up` first (we start an 80x24 session + server) and then delivers the client's `pty_req` with the real dimensions. The previous `pty_req` handler created a brand-new `Session` on every call, which left the SSH channel pointing at a session the running Server no longer rendered into. The handler now splits on `session: nil` vs `session: %Session{}` and resizes the existing session in place when one is already there, mirroring the `window_change` path
- **SSH subsystem pty-size discovery on nerves_ssh** — even with the pty_req race fixed, a subsystem TUI riding on `nerves_ssh` (or any `:ssh.daemon` that configures a default CLI handler) would stay stuck at the hardcoded 80x24 fallback instead of filling the client's real terminal. Root cause: OTP `:ssh_connection.handle_cli_msg/3` hands pty_req to the daemon's default CLI handler when the channel's user pid is still `undefined`, and then silently orphans that CLI handler the moment the subsequent subsystem request rebinds the pid to us — so the subsystem handler *never* sees pty_req on those deployments, no matter how early it arrives. `ExRatatui.SSH` now sidesteps the whole OTP path by emitting a Cursor Position Report roundtrip (`ESC[s ESC[9999;9999H ESC[6n ESC[u`) on `{:ssh_channel_up, ...}`: the client clamps the bogus cursor position to its real pty size, responds with `ESC[<row>;<col>R`, the session's ANSI input parser decodes that as a `%ExRatatui.Event.Resize{}`, and the `{:data, ...}` handler resizes the session in place + notifies the running server via `{:ex_ratatui_resize, w, h}`. Shell-mode startup is unaffected — it still reads the dimensions straight off `pty_req`
- **`session_input.rs` CPR parsing** — the VTE-driven input parser now recognizes `ESC[<row>;<col>R` Cursor Position Report responses and emits them as `NifEvent::Resize(col, row)` so the SSH transport's CPR-based pty-size discovery has something to intercept. The handler runs before the simple-CSI dispatch that would otherwise silently drop any `R` final byte
- **SSH subsystem startup** — added a shell-vs-subsystem section to `ExRatatui.SSH`'s moduledoc and the `guides/ssh_transport.md` guide explaining which message triggers server boot in each mode, plus a loud "always pass `-t`" caveat (OpenSSH doesn't allocate a PTY for subsystem invocations by default, which leaves the client's local terminal in cooked mode — keystrokes get line-buffered and echoed locally on top of the TUI)

## [0.6.0] - 2026-04-09

### Added

- **SSH transport** — serve any `ExRatatui.App` to remote clients over OTP `:ssh`. New `transport: :ssh` option on `ExRatatui.App` and a standalone `ExRatatui.SSH.Daemon` for direct supervision-tree use. Each connected client gets its own isolated TUI session; works as a primary daemon or as a `nerves_ssh` subsystem via `ExRatatui.SSH.subsystem/1`
- `ExRatatui.Session` — in-memory transport-agnostic terminal session (Rust `SharedWriter` + `Viewport::Fixed`) with `new/2`, `draw/2`, `take_output/1`, `feed_input/2`, `resize/3`, `size/1`, and `close/1`
- `ExRatatui.SSH` — `:ssh_server_channel` implementation that drives a Session per channel, parses ANSI input via `vte`, and handles PTY negotiation, `window_change`, and alt-screen lifecycle
- `ExRatatui.SSH.Daemon` — GenServer wrapping `:ssh.daemon/2` with `port/1` and `daemon_ref/1` introspection helpers
- `ExRatatui.SSH.Daemon` `:auto_host_key` option — when set, the daemon resolves the OTP application that owns `:mod`, ensures `<priv_dir>/ssh/` exists, and generates a 2048-bit RSA host key on first boot. Subsequent boots reuse the same key. Lets Phoenix admin TUIs and similar drop the daemon straight into a supervision tree without hand-rolling host-key bootstrap
- `ExRatatui.SSH.Daemon` `:system_dir` accepts binary paths in addition to charlists; the daemon converts them before forwarding to `:ssh.daemon/2`
- VTE-based input parser covering arrows, function keys, SS3, CSI modifiers, Alt+letter, Ctrl+letter, and partial-sequence buffering across feeds (SSH delivers byte-at-a-time during interactive use)
- 7 new session NIFs on ExRatatui.Native: `session_new/2`, `session_close/1`, `session_draw/2`, `session_take_output/1`, `session_feed_input/2`, `session_resize/3`, `session_size/1`
- Guide: `guides/ssh_transport.md` — architecture, quick start, `nerves_ssh` integration, options reference, host-key generation, troubleshooting
- Examples ship an SSH mode: `examples/system_monitor.exs --ssh` and `examples/task_manager` via `TASK_MANAGER_SSH=1` (multiple clients share one SQLite database)
- README "Running Over SSH" section
- CI enforces 100% Elixir test coverage threshold (NIF modules excluded)
- Missing doctests for `ExRatatui`, `Event`, `Event.Key`, `Event.Mouse`, `Event.Resize`, and `SlashCommands`
- Callback documentation for all `ExRatatui.App` callbacks

### Changed

- ExRatatui.Server learns a `transport: :local | :ssh` option and an alternate `init/1` path that drives an injected Session + writer function instead of the local terminal
- `ExRatatui.App` gains a `:transport` option that dispatches between ExRatatui.Server `start_link/1` and `ExRatatui.SSH.Daemon.start_link/1`

### Docs

- Expanded moduledoc prose for `ExRatatui`, `Event`, and event struct modules
- Added coverage requirement note to CONTRIBUTING.md

### Tests

- Bumped Elixir test coverage to 100% — added server, rendering, layout, event, and widget tests
- End-to-end SSH integration test exercising `:ssh.daemon/2` + `:ssh.connect/3` round trip with a generated host key (mount → render bytes → keystroke roundtrip → window_change)

## [0.5.1] - 2026-03-25

### Added

- `ExRatatui.Widgets.Markdown` — markdown rendering widget with syntax-highlighted code blocks, powered by `tui-markdown` (pulldown-cmark + syntect)
- `ExRatatui.Widgets.Textarea` — multiline text editor with undo/redo, cursor movement, and Emacs-style shortcuts. Second **stateful** widget — state lives in Rust via ResourceArc
- `ExRatatui.Widgets.Throbber` — loading spinner widget with 12 animation sets (braille, dots, ascii, arrow, clock, and more)
- `ExRatatui.Widgets.Popup` — centered modal overlay widget for dialogs, confirmations, and command palettes
- `ExRatatui.Widgets.WidgetList` — vertical list of heterogeneous widgets with selection and scrolling, ideal for chat message histories
- `ExRatatui.Widgets.SlashCommands` — slash command parsing, matching, and autocomplete popup rendering
- Textarea NIF functions: `textarea_new/0`, `textarea_handle_key/3`, `textarea_get_value/1`, `textarea_set_value/2`, `textarea_cursor/1`, `textarea_line_count/1`
- Example: `chat_interface.exs` — AI chat interface demonstrating Markdown, Textarea, Throbber, Popup, WidgetList, and SlashCommands

### Fixed

- Replaced deprecated `Padding::zero()` with `Padding::ZERO` in Rust widget renderers
- Wired up unused `style` field in `WidgetList` render function (was `#[allow(dead_code)]`)
- Fixed flaky Rust throbber step test — `calc_step(0)` uses random index, now tests with deterministic non-zero steps
- Throbber animation set test now covers all 12 sets (was 7)

## [0.5.0] - 2026-03-22

### Added

- `ExRatatui.Widgets.Tabs` — a tab bar widget for switching between views, with customizable selection highlight, divider, and padding
- `ExRatatui.Widgets.Scrollbar` — a scrollbar widget for indicating scroll position, supporting all four orientations (vertical right/left, horizontal bottom/top)
- `ExRatatui.Widgets.LineGauge` — a thin single-line progress bar using line-drawing characters, with separate filled/unfilled styles
- `ExRatatui.Widgets.Checkbox` — a checkbox widget for boolean toggles, with customizable checked/unchecked symbols and styles
- `ExRatatui.Widgets.TextInput` — a single-line text input widget with cursor navigation, viewport scrolling, and placeholder support. First **stateful** widget — state lives in Rust via ResourceArc
- Example: `widget_showcase.exs` — interactive demo with tabs, progress bars, checkboxes, text input, scrollable logs, and scrollbar (replaces individual `tabs_demo.exs`, `scrollbar_demo.exs`, `line_gauge_demo.exs`)
- Doctests for `Tabs`, `Scrollbar`, `LineGauge`, and `Checkbox` struct modules
- Updated `task_manager.exs` example to use `Tabs` (header), `LineGauge` (progress), `Scrollbar` (task table), and `TextInput` (new task creation — replaces hand-rolled input buffer with proper cursor navigation, viewport scrolling, and placeholder support)
- Updated `examples/task_manager/` App to use `Tabs` (filter bar with Tab/Shift+Tab navigation), `LineGauge` (replaces `Gauge`), `Scrollbar` (task table), and `TextInput` (replaces hand-rolled input buffer)
- Comprehensive `TextInput` state management tests: get/set value, cursor positioning, backspace, delete, left/right, home/end, and mid-text insertion

### Fixed

- `Checkbox` moduledoc now correctly states that `:checked_symbol` and `:unchecked_symbol` default to `nil` (rendered as `"[x]"` / `"[ ]"` by the Rust backend)
- Removed redundant `.padding()` call in Rust tabs renderer that was always overwritten

## [0.4.2] - 2026-03-06

### Added

- `ExRatatui.Widgets.Clear` — a widget that resets all cells in its area to empty (space) characters, useful for rendering overlays

### Fixed

- Put back `Elixir.` prefix from `List` calls in `task_manager.exs` example

## [0.4.1] - 2026-02-23

### Fixed

- `init_terminal` NIF now cleans up raw mode and alternate screen on partial initialization failure
- All I/O-bound NIFs (`init_terminal`, `restore_terminal`, `draw_frame`, `terminal_size`) now run on the DirtyIo scheduler to avoid blocking normal BEAM schedulers
- `App.render/2` callback typespec narrowed from `term()` to `ExRatatui.widget()` for proper Dialyzer coverage
- `Constraint::Ratio` with denominator zero now returns an error instead of panicking
- `Gauge` ratio now validates the value is finite, preventing a panic on NaN input
- `App.mount/1` callback typespec now includes `{:error, reason}` return
- `ExRatatui.run/1` `after` block no longer masks the original exception if terminal restore also fails
- Server render errors now log the full stacktrace for easier debugging
- Added missing `@impl true` on fallback `terminate/2` clause in the server
- `ExRatatui.Frame` struct defaults to `width: 0, height: 0` instead of `nil` (typespec now matches actual usage)
- Deduplicated `encode_constraint/1` — `ExRatatui.Layout` is now the single source of truth
- Fixed flaky `poll_event` tests that failed when terminal events arrived during the test run
- `Event.Mouse` typespec fields are now non-nullable to match actual NIF output
- Fixed `system_monitor.exs` to cache hostname between refreshes with `Map.get_lazy/3`
- Removed unnecessary `Elixir.` prefix from `List` calls in `task_manager.exs` example
- Added server tests for `{:stop, state}` from `handle_info/2` and `terminate/2` callback

### Docs

- HexDocs "View Source" links now point to the correct version tag
- Expanded `ExRatatui` moduledoc with quick start, core API overview, and cross-references
- README demo GIF now uses an absolute URL so it renders on Hex.pm
- README modifiers list now shows all six supported modifiers
- Documented `:test_mode` option in `ExRatatui.App` for headless testing
- Clarified `system_monitor.exs` is Linux/Nerves only in README

## [0.4.0] - 2026-02-23

### Changed

- **BREAKING**: Terminal state is now per-process via Rust ResourceArc instead of a global mutex
  - `ExRatatui.run/1` closure now receives the terminal reference (1-arity)
  - `draw/1` is now `ExRatatui.draw/2` (terminal reference as first argument)
  - `ExRatatui.init_test_terminal/2` returns a terminal reference instead of `:ok`
  - `get_buffer_content/0` is now `ExRatatui.get_buffer_content/1`
  - `ExRatatui.App` behaviour users: **no API changes**
- Terminal is automatically restored when the terminal reference is garbage collected (crash safety)
- Test terminal instances are now independent, enabling `async: true` for rendering tests

### Added

- Comprehensive API documentation: all key codes, mouse events, colors, modifiers, and App options
- Doctests for Layout, Style, Frame, all widgets, and test backend
- CONTRIBUTING.md with development setup

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

[Unreleased]: https://github.com/mcass19/ex_ratatui/compare/v0.6.2...HEAD
[0.6.2]: https://github.com/mcass19/ex_ratatui/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/mcass19/ex_ratatui/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/mcass19/ex_ratatui/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/mcass19/ex_ratatui/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/mcass19/ex_ratatui/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/mcass19/ex_ratatui/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/mcass19/ex_ratatui/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/mcass19/ex_ratatui/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/mcass19/ex_ratatui/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mcass19/ex_ratatui/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/mcass19/ex_ratatui/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mcass19/ex_ratatui/releases/tag/v0.1.0
