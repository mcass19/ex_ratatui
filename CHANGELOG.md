# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Project logo.** New logo assets under `assets/` (`logo` mark and `logo_letters` wordmark, each as SVG/PNG/JPG). The README header is now centered — logotype, then description, then badges — and the logo mark appears next to the project name in the hexdocs sidebar (via the ex_doc `:logo` option, which ships `assets/logo.png` in the Hex package).

- **3D rendering with `ExRatatui.Widgets.Viewport3D`.** A new pure-data widget renders lit 3D scenes — built-in `cube`/`sphere`/`plane`/`cylinder` primitives and custom meshes, Phong materials, ambient/directional/point lights, and a perspective camera — using a software rasterizer or CPU ray tracer, blitted into true-color cells via half-block, supersampled-braille, or ASCII modes. Scene types live under `ExRatatui.ThreeD.*` (`Scene`, `Object`, `Mesh`, `Material`, `Light`, `Camera`, `Transform`), with pure `Camera.orbit/3` and `Camera.zoom/2` helpers. Built on the vendored [ratatui-3d](https://github.com/limlabs/ratatui-3d) renderer; the GPU pipeline is intentionally not exposed. Requires a true-color terminal. See the [3D Rendering](guides/core/3d.md) guide and the `examples/widgets/viewport3d_*.exs` examples.

- **Scene-graph for articulated models.** `ExRatatui.ThreeD.Node` composes a tree of local transforms and flattens to the flat `Scene` (`flatten/1`, `to_scene/2`), backed by `ExRatatui.ThreeD.Transform.compose/2`. Keep intermediate frames rigid and scale only leaf visuals, and every baked object stays a single `Transform`. See `examples/widgets/viewport3d_articulated.exs`.

- **Pixel-graphics rendering for `Viewport3D`.** `render_mode` now also accepts terminal image protocols — `:auto` (the new default), `:kitty`, `:sixel`, `:iterm2` — rendering the scene as a true-resolution image (crisp, non-blocky) on capable terminals (Ghostty/WezTerm/Kitty), and automatically falling back to `:braille` over CellSession/Livebook, distributed/SSH without passthrough, or unsupported terminals. The cell-blit modes (`:half_block`, `:braille`, `:ascii`) remain available. Reuses the same protocol stack as `ExRatatui.Image`.

## [0.10.2] - 2026-06-12

### Added

- **Per-widget example isolates — every built-in widget now has a focused, copyable demo.** New standalone examples under `examples/widgets/` cover the widgets that previously only appeared inside large multi-tab or app examples: `barchart`, `sparkline`, `chart`, `calendar`, `canvas`, `checkbox`, `gauge`, `line_gauge`, `scrollbar`, `tabs`, `list`, `markdown`, `popup`, `widget_list`, `slash_commands`, `textarea`, and `clear`. Each is a short, single-purpose script so a widget can be lifted out without untangling it from a larger app.

- **Two guide companions under `examples/observability/`.** `telemetry.exs` attaches a `:telemetry` handler to the runtime's own render/event `:stop` spans and renders the live event counts — a runnable counterpart to the Telemetry guide. `state_machine.exs` demonstrates the screen-as-data dispatch and modal-overlay patterns from the State Machine Patterns guide (a `:screen` atom names the active state; an `:overlay` field intercepts input for a confirm-quit `Popup`). `throbber.exs` runs on the reducer runtime, driving its animation from a `Subscription.interval`.

- **Examples catalog published to hexdocs.** `examples/README.md` is now an `ExDoc` extra titled **Examples**, grouped by folder with a "Start here" on-ramp, so the catalog is reachable from the published docs and not just GitHub.

- **`usage-rules.md` ships in the Hex package** (and as a docs extra) for downstream AI-agent context.

- **Architecture guide.** New `guides/internals/architecture.md` documents the NIF bridge (encode/decode pipeline, DirtyIo event polling, `ResourceArc` terminal state, layout on the Rust side) and the per-transport process trees — content previously squeezed into the README's "How It Works" section, now a first-class hexdocs page. The [Callback Runtime](guides/runtimes/callback_runtime.md) guide gained a "Callback or Reducer?" comparison table (moved from the README) that the Reducer guide links to.

- **Elixir 1.20 compatibility** — 1.20 compiler warnings are resolved and 1.20 is part of the CI matrix.

### Changed

- **README rewritten around a scannable feature list.** The ~22-bullet Features section (several of them paragraph-length, with API signatures inline) is now 14 one-line `**capability** — description` bullets in the style of Oban's README; every dropped detail already lives in a guide or the cheatsheet. The "Choosing a Runtime" and "Choosing a Transport" tables moved to the guides (the runtime table to [Callback or Reducer?](guides/runtimes/callback_runtime.md#callback-or-reducer), the transport story to the [Transports](guides/transports/transports.md) matrix), replaced by a short "Runtimes and Transports" section that links them. "How It Works" shrank to a two-sentence summary pointing at the new Architecture guide. The standalone Examples section is gone (Quick Start already links the catalog), and sections now follow the conventional flow: Features → Installation → Quick Start → Runtimes and Transports → Guides → How It Works → Ecosystem → Built with → Contributing.

- **One documentation voice and shape.** Prose across the guides, README, cheatsheet, and moduledocs no longer addresses the reader as "you" — imperative or subjectless phrasing throughout (the Getting Started tutorial keeps its conversational register). Section headings are sentence case, every guide closes with the same "Related" section, and footer links share one plain-link style.

- **Guides deduplicated — each fact now lives in one place.** The reducer guide defers to the callback guide for the error-handling, transports, and testing sections they shared verbatim, keeping only its deltas; intents are documented once instead of three times. The SSH and Distributed guides' shared "multiple transports" and "app_opts forwarding" sections moved into the canonical [Transports](guides/transports/transports.md) guide; ssh_transport's retellings of the `ExRatatui.SSH` moduledoc (pty_req story, CPR walkthrough, `auto_host_key` ×3) collapsed to the user-facing facts. Building UIs' 530-line per-widget catalog — a near-1:1 duplicate of the cheatsheet — is now a purpose-grouped index plus the pattern-teaching subsections (stateful inputs, overlays, WidgetList scrolling, slash commands); its constraint table gained the missing `{:fill, weight}` and `split/4` opts. The telemetry event catalog is canonical in `ExRatatui.Telemetry`'s moduledoc (which gained the image/code_block spans) with the guide keeping the narrative. Rot-prone internals dropped throughout: Rust enum names and upstream symbols in the images guide, NIF tuple shapes, hardcoded source line references, hardware-dependent timings, version-specific migration notes.

- **Guides reorganized into grouped subfolders.** The flat `guides/` directory is now grouped into `introduction/`, `core/`, `runtimes/`, `transports/`, and `internals/` (plus the existing `cheatsheets/`), and the hexdocs sidebar mirrors the same structure: **Introduction** (Getting Started, Examples), **Building UIs**, **Runtimes**, **Transports**, **Going Deeper**, and **Cheatsheets** replace the single flat **Guides** group. Page filenames are unchanged, so existing hexdocs URLs keep working; only in-repo paths moved (e.g. `guides/building_uis.md` → `guides/core/building_uis.md`).

- **Examples reorganized into grouped subfolders.** The flat `examples/` directory is now grouped into `basics/`, `widgets/`, `layout/`, `apps/`, `cell_session/`, `images/`, and `observability/`. Run paths change accordingly — e.g. `mix run examples/counter_app.exs` is now `mix run examples/basics/counter_app.exs`. Notable moves and renames: the 1066-line `widget_showcase.exs` is **retired** in favor of the per-widget isolates above, `chat_interface.exs` → `apps/chat.exs`, `data_table.exs` → `widgets/table.exs`, and the Ecto `task_manager/` app → `apps/task_manager_db/`. The full mapping is reflected in the examples catalog.

- **`native/ex_ratatui/Cargo.lock` is committed** for reproducible NIF builds from source.

### Fixed

- **`usage-rules.md` covers the silent-failure key vocabulary.** The rules file now leads its gotcha list with the lowercase-string contract for `Event.Key` / `Event.Mouse` fields (`code: "up"`, `modifiers: ["ctrl"]` — wrong values compile and never match), indexes `ExRatatui.Focus`, `ExRatatui.Theme`, and `ExRatatui.CellSession` so agents stop hand-rolling them, and corrects the same `commands:`/`render?:` reducer-only claim fixed across the other docs.

- **Six modules' doc examples now run as doctests.** `ExRatatui.Command`, `ExRatatui.Subscription`, `ExRatatui.Image` (`render_size/4`), `ExRatatui.Widgets.BarGroup`, `ExRatatui.Widgets.Canvas.Map`, and `ExRatatui.Widgets.Canvas.Label` all carried `iex>` examples that were never wired into the suite (Canvas.Line/Rectangle/Circle/Points were — Map and Label were an oversight). `ExRatatui.Distributed`'s quick-start transcript dropped its `iex>` prompt so the side-effecting `attach/2` line can never be picked up as a doctest.

- **Documentation accuracy pass — every code snippet verified against the API.** Roughly 25 factual errors across the guides, the cheatsheet, and the moduledocs are fixed:
  - *Snippets that raised or silently never matched on copy-paste*: `%Event.Key{modifiers: [:ctrl]}` → modifiers are strings (`["ctrl"]`); `%Event.Mouse{column:, row:}` → fields are `x`/`y` with string `kind`/`button`; `%Event.Resize{columns:, rows:}` → `width`/`height`; `Command.async(fun, :atom)` → the mapper must be an arity-1 function; a `Task.Supervisor.async_nolink` example that sent its result to the task's own pid; the Images quick start used a nonexistent `view/2` callback; `Focus` caller examples (guide and moduledoc) returned bare `state` instead of `{:noreply, state}`.
  - *Wrong claims*: the runtime comparison table said tracing is reducer-only (snapshot/trace/inject work under both runtimes); `commands:`/`render?:` were documented as no-ops under the callback runtime but the server executes them for both — docs now describe the actual behaviour; the reducer guide claimed `init/1` and `update/2` have defaults (they're required); the debugging guide inverted `:transient` restart semantics; `poll_event/1`'s doc and `Event.FocusGained` claimed focus reporting is default-on (it's opt-in via `focus_events: true`); the transports matrix wrote `:iterm` for `:iterm2` and atom shorthand for tuple transport shapes; the distributed guide mis-ordered the attach sequence; WidgetList docs claimed only visible rows cross the NIF boundary (encoding walks all items).
  - *Silent-zero telemetry examples*: three `Telemetry.Metrics` definitions pointed at event/measurement names that never fire; the default-logger doc now notes the image/code_block spans are excluded.
  - *Stale references*: the SSH and Distributed option tables were missing `image_protocol`/`image_font_size`; the quoted `server_transport` contract in Custom Transports lagged the Server (and `ExRatatui.Transport`'s typespec gained the 4-tuple `:cell_session` intent variant the Server already accepted); phantom file/function names (`continue_init_ssh/3`, `test/property/`, pre-reorg example paths) and three broken anchors/relative links.

## [0.10.1] - 2026-06-01

### Added

- **`ExRatatui.Theme` — pure-data palette struct (Layer A theming).** Eleven semantic slots (`:primary`, `:accent`, `:border`, `:border_focused`, `:surface`, `:surface_alt`, `:text`, `:text_dim`, `:success`, `:warning`, `:danger`) each accepting the full `t:ExRatatui.Style.color/0` shape (named atoms, `{:rgb, r, g, b}`, `{:indexed, n}`, or `nil`). Two starter constructors ship: `default/0` (terminal-respecting; `surface: nil` so the same theme works on light and dark terminals) and `light/0` (dark text on white surface). Three composition helpers cover the common patterns: `border_style(theme, focused: true|false)`, `text_style(theme, dim: true|false)`, `selection_style(theme)`. Apps thread the theme through render code by hand — no `Application.get_env` magic, no automatic widget injection. Layer B (opt-in per-widget defaults at render time) is intentionally deferred.

- **Bracketed paste (`%ExRatatui.Event.Paste{content: binary}`).** `ExRatatui.run/2` enables crossterm's `EnableBracketedPaste` on init and disables it on restore. The local terminal's `poll_event/1` decodes `Event::Paste(String)` into a new `%Event.Paste{}` struct so pasted multi-line / multi-byte content arrives as one event instead of being shredded across individual keystrokes. Two batch-insert NIFs consume the payload in one shot: `ExRatatui.text_input_insert_str/2` (single-line — strips every control char) and `ExRatatui.textarea_insert_str/2` (multi-line — `\n` and `\r\n` become real new lines via `ratatui_textarea::insert_str`; lone `\r` is dropped). Pasting a 5,000-character URL is now one NIF call rather than 5,000. Best-effort: terminals without bracketed paste ignore the request and the per-char keystream still arrives — apps don't need a conditional path. Out of scope this release: bracketed paste decode on the byte-stream input parser used by `:session` / `:ssh` / `:distributed` transports — their custom VTE state machine doesn't decode `CSI 200~/201~` markers yet, so apps on those transports construct `%Event.Paste{}` directly and feed it into their event pipeline.

- **`%ExRatatui.Event.FocusGained{}` / `%ExRatatui.Event.FocusLost{}` — terminal-window focus reporting.** Opt-in via `ExRatatui.run(fun, focus_events: true)`. When enabled, crossterm emits focus events as the parent emulator window gains or loses focus; apps use them to pause expensive animations / background ticks while the user is elsewhere. Two separate payload-less structs (matching crossterm's variant shape, and avoiding any clash with the existing `ExRatatui.Focus` module). **Off by default**: enabling focus reporting leaves `CSI ?1004h` on the user's tty, and any window-switch queues focus bytes that leak back into unrelated stdin consumers (a plain shell or `mix test` started later) as `^[[I` / `^[[O` sequences. Same upstream caveat as bracketed paste: only the local terminal decodes these; byte-stream transports would need VTE-parser work.

- **Local-terminal mouse capture is now opt-in via `ExRatatui.run(fun, mouse_capture: true)`.** When enabled, crossterm's `EnableMouseCapture` reports clicks / scroll / drag / move as `%Event.Mouse{}` from `poll_event/1`. **Off by default** because mouse-reporting mode captures the terminal's native text selection — the user can no longer select and copy text the usual way until the app exits. `ExRatatui.Server.start_link` (and therefore every `ExRatatui.App`) accepts the same `:mouse_capture` and `:focus_events` opts for the `:local` transport. SSH and Distributed transports decode mouse sequences unconditionally because their VTE-based input parser handles them regardless of this flag — Focus.handle_mouse/2 has always worked there.

- **`ExRatatui.Focus` gains mouse routing.** New fields and functions extend the existing keyboard focus ring with a `regions: %{id => Rect}` map and `handle_mouse/2`. Apps register hit-test regions after computing layout (typically inside a `%Event.Resize{}` handler) via `Focus.set_region/3` or `Focus.set_regions/2`; `Focus.handle_mouse/2` mirrors `handle_key/2` shape — on a left-button-down inside a registered region, focus moves to that ID and the event is **passed through** so the underlying widget can still react (toggle a checkbox, place a cursor, start a drag). Every other mouse kind (right/middle click, scroll, drag, move, up) is pass-through with focus untouched. `Focus.at/3` exposes the same hit-test for apps that prefer "scroll the widget under the cursor" over "scroll the focused widget". Overlapping regions resolve to the smallest by area (leaf-inside-container picks the leaf). Boundaries are half-open (`x >= rx and x < rx + w`) — natural for ratatui rect semantics.

- **`%ExRatatui.Widgets.Block.Title{}` + multi-title support on Block.** Four new Block fields close the most-asked ergonomics gap: `:titles` (list of additional titles, each a `%Block.Title{content, position, alignment, style}` struct OR a raw line-like value that inherits the block defaults), `:title_position` (`:top` default, `:bottom`), `:title_alignment` (`:left` default, `:center`, `:right`), `:title_style` (default `%Style{}` for any title without its own). Backward compatible — the existing `:title` field stays a single-title shortcut at the block's default position and alignment. The classic "filename | scroll %" header is `title: "filename", titles: [%Block.Title{content: "[3/12]", alignment: :right}]`. All title fields validated at Bridge encode with `ArgumentError`; entries in `:titles` that are neither `%Block.Title{}` nor line-like are rejected with a descriptive message.

- **Eight additional `Block` border types.** Beyond `:plain` / `:rounded` / `:double` / `:thick`, the widget now accepts `:light_double_dashed`, `:heavy_double_dashed`, `:light_triple_dashed`, `:heavy_triple_dashed`, `:light_quadruple_dashed`, `:heavy_quadruple_dashed` (the border line broken into 2/3/4 dash segments) and `:quadrant_inside` / `:quadrant_outside` (blocky half-cell borders drawn inside or outside the content area). Closes the upstream `BorderType` surface — every ratatui variant is now reachable.

- **Layout `:margin` / `:horizontal_margin` / `:vertical_margin` opts.** `ExRatatui.Layout.split/4` can now inset the area before splitting — `margin: 1` leaves a 1-cell border on all four sides; `:horizontal_margin` / `:vertical_margin` override per-axis. Complements the existing `:spacing` (gaps *between* segments). Validated from Elixir like the other opts.

- **Style `:underline_color`.** `%ExRatatui.Style{}` gains an `:underline_color` field — the color of the underline drawn by the `:underlined` modifier, distinct from `:fg`. `nil` (default) uses the foreground color. Honoured by terminals with colored-underline support (kitty, wezterm); others fall back to a plain underline.

- **`ExRatatui.Layout.Padding` ergonomic constructors.** `uniform/1`, `symmetric/2` (horizontal, vertical), `horizontal/1`, `vertical/1`, and `new/4` return the `{left, right, top, bottom}` tuple that `Block`'s `:padding` field already accepts — `%Block{padding: Padding.uniform(1)}` instead of `padding: {1, 1, 1, 1}`. Pure functions, no struct, no runtime cost beyond building the tuple.

- **`ExRatatui.set_terminal_title/1`.** Sets the terminal window / tab title via OSC 0/2 (crossterm `SetTitle`). Useful for daemon TUIs, dashboards, and multi-tab terminals. Best-effort: terminals that don't honour the escape ignore it. One new NIF `set_terminal_title/1`.

- **Layout Flex modes + `Constraint::Fill` + segment spacing.** `ExRatatui.Layout.split/4` adds two keyword opts: `:flex` (one of `:legacy`, `:start`, `:end`, `:center`, `:space_between`, `:space_around`) and `:spacing` (non-negative cells inserted between every pair of adjacent segments). New constraint shape `{:fill, weight}` distributes the leftover space after higher-priority constraints (Length / Percentage / Ratio / Min / Max) are satisfied — `{:fill, 1}` + `{:fill, 2}` splits the remainder 1:2. Unlocks centered popups (`flex: :center`), end-aligned status bars (`flex: :end`), evenly-spaced toolbars (`flex: :space_between`), growable dashboard panels (`{:fill, 1}` / `{:fill, 2}`), and gutters between segments (`spacing: 2`). Backward compatible: existing `Layout.split/3` calls land via default opts. Both opts raise `ArgumentError` from Elixir on invalid values.

- **List: `:direction`, `:scroll_padding`, `:repeat_highlight_symbol`.** `direction: :bottom_to_top` paints the first item at the bottom of the area and grows upward — natural for chat logs, REPL history, and event streams where the newest entry pins to the bottom edge. `scroll_padding` keeps the selected item at least N rows from the viewport edge when the list auto-scrolls (same idea as vim's `scrolloff`). `repeat_highlight_symbol: true` repeats the highlight symbol on every wrapped row of a multi-line item instead of only the first. All three validated at Bridge encode.

- **Table: `:footer`, `:header_style`, `:footer_style`, `:column_highlight_style`, `:cell_highlight_style`, `:selected_column`, `:highlight_spacing`.** Footer renders at the bottom of the area; header / footer styles override the table's `:style` for those rows. `column_highlight_style` / `cell_highlight_style` paint the selected column / cell (intersection of selected row + column) — useful for spreadsheet-style navigation. `:selected_column` is the gating field for the column / cell styles: without it the styles never fire (ratatui's `TableState::select_column/1` is the activation mechanism). Validated like `:selected` against the widest of widths / header / first-row column count. `highlight_spacing` (`:always`, `:when_selected` default — matches ratatui, `:never`) controls when the symbol column is reserved; `:always` pins column positions even when nothing is selected so the row doesn't shift on select.

- **Three new examples covering the round-1 surface end-to-end:**
  - [`examples/chat_log.exs`](examples/chat_log.exs) — `%List{direction: :bottom_to_top}` history pinned to the bottom edge, multi-line `%Textarea{}` composer with bracketed paste support via `textarea_insert_str/2`, multi-title `%Block{}` header with right-aligned unread count, Tab-cycled focus between log and composer.
  - [`examples/data_table.exs`](examples/data_table.exs) — every new Table field on one screen: footer, header / footer styles, column / cell highlight styles wired to a live `:selected_column`, and `:highlight_spacing: :always`. Arrow keys move the row + column cursor.
  - [`examples/theme_picker.exs`](examples/theme_picker.exs) — visual reference for every `ExRatatui.Theme` slot plus a live preview rendering `border_style/2` (focused + unfocused), `text_style/2` (default + dim), and `selection_style/1` in real widgets. Press 1/2/3 to switch between `default/0`, `light/0`, and a custom Nord-ish theme.

- **Numeric input validation pass on every bounded widget.** `Gauge` and `LineGauge` raise `ArgumentError` when `:ratio` is outside `0.0..1.0` or not a number (integers `0` and `1` still coerce to floats — the existing "clamped automatically" moduledoc note was a lie and now matches behavior). `List`, `Table`, `Tabs`, `WidgetList` reject `:selected` values that are not `nil` or an integer in `0..length(items) - 1`; empty collections get a distinct error message (`"expected nil (collection is empty)"`). Failures surface from Elixir with `widget.field` context strings instead of a downstream Rust panic. `Sparkline` and `BarChart` numeric validation was already in place — this pass closed the remaining gaps.

- **`test/ex_ratatui/property/widget_render_property_test.exs` — per-widget property invariants.** Two `ExUnitProperties` properties stress every stateless widget type the library ships (24 of 29 total): `Bridge.encode_commands!/1` accepts arbitrary valid inputs at any rect, and `CellSession.draw + take_cells` produces a snapshot with exactly `width × height` cells. Covers Paragraph, Block, Clear, List, Table, Gauge, LineGauge, Tabs, Sparkline, BarChart, Throbber, Scrollbar, Checkbox, Calendar, Markdown, BigText, plus the stateful TextInput / Textarea / Image and composite Popup / WidgetList / Canvas / CodeBlock. Chart is intentionally excluded from the render property — upstream ratatui panics on multiple Chart input combinations (narrow axis bounds, empty datasets, `:bar` graph_type with sparse data, small rects after block borders) and proving "Chart never panics" isn't a guarantee the rendering layer can give. The encode property still covers Chart at any rect.

- **`guides/transports.md` — canonical cross-transport feature matrix.** Five-row transport table introduces each entry point (`Local`, `Session`, `SSH`, `Distributed`, `CellSession`); 14-row feature matrix covers widget rendering, every `Event.*` variant, image protocols + auto-probe, OSC 52 clipboard, intents, runtime opts, and telemetry — with three states (✓ supported, — not applicable, ✗ known gap) and inline notes on every gap row. Replaces the implicit assumption that the per-transport guides spell this out; they don't, and now they don't have to.

- **`guides/paste_and_clipboard.md`.** Walks through bracketed paste behaviour, the two `insert_str` helpers, the SSH / distributed transport caveat, and ships a short OSC 52 snippet for apps that want clipboard copy without bundling another module. OSC 52 is **not** built into the library — too many opinions in the ecosystem (system clipboard via `arboard`, OSC 52, route through a Phoenix LiveView intent). The guide is the canonical place to discover the snippet.

### Changed

- **`Native.init_terminal` arity bumped to 2** — `(focus_events :: bool, mouse_capture :: bool)`. `ExRatatui.run/1` becomes `ExRatatui.run/2` accepting `:focus_events` and `:mouse_capture` opts; `run/2` with no opts is equivalent to the old `run/1`. `ExRatatui.Server.start_link` (and every `ExRatatui.App`) accepts the same two opts for the `:local` transport. The `init_terminal/0` form is gone — direct NIF callers (custom transports, examples) must pass both booleans explicitly.

- **`[:ex_ratatui, :transport, :connect]` span metadata gains `:focus_events` and `:mouse_capture`** for the `:local` transport, reflecting the boolean opts the app started with. Other transports' connect metadata is unchanged.

- **`ExRatatui.Widgets.Block` defaults.** `defstruct` now includes `:titles`, `:title_position`, `:title_alignment`, `:title_style` with backward-compatible defaults (`[]`, `:top`, `:left`, `nil`). Apps constructing blocks with `%Block{...}` and only the old fields are unaffected; the doctest in `Block.moduledoc` shows the new shape.

- **`ExRatatui.Widgets.List` defaults.** `defstruct` adds `:direction` (`:top_to_bottom`), `:scroll_padding` (`0`), `:repeat_highlight_symbol` (`false`). Matches ratatui's defaults.

- **`ExRatatui.Widgets.Table` defaults.** `defstruct` adds `:footer` (`nil`), `:column_highlight_style` (`nil`), `:cell_highlight_style` (`nil`), `:header_style` (`nil`), `:footer_style` (`nil`), `:highlight_spacing` (`:when_selected` — matches ratatui).

- **Rust-side `BlockData`, `ListData`, `TableData` gain `Default` impls.** Test fixtures and Rust callers (one per widget that composes a Block) shrink to `..Default::default()` — same backward-compat guarantee inside the native code as on the Elixir side.

## [0.10.0] - 2026-05-19

### Added

- **`ExRatatui.Widgets.CodeBlock` — syntax-highlighted source code.** Display-only widget powered by [syntect](https://github.com/trishume/syntect)'s bundled `SyntaxSet` and `ThemeSet`. Fields: `:content`, `:language` (any syntect token name; `nil` for plain text fallback), `:theme` (seven curated atoms — `:base16_ocean_dark`, `:base16_ocean_light`, `:base16_eighties_dark`, `:base16_mocha_dark`, `:inspired_github`, `:solarized_dark`, `:solarized_light` — or any raw string for custom theme sets), `:line_numbers` + `:starting_line` (right-aligned dim gutter with `│` separator, width grows with the last visible line), `:highlight_lines` (list of ints + ranges like `[3, 7..9]`, normalised to a sorted unique list, rendered with a theme-derived background that brightens dark themes and dims light themes by 20/256 per channel). Composes with `Block`, `Popup`, and `WidgetList` like every other widget. One new widget type (`"code_block"`) on the render decoder.

- **`ExRatatui.CodeBlock.highlight/3` — raw highlighted lines for composite widgets.** Returns `[%ExRatatui.Text.Line{}]` with per-token styled spans for callers building DiffViewer / Inspector-style composites without dropping a full `CodeBlock` in the tree. Backed by a single new NIF `highlight_code/3` (scheduled on `DirtyCpu`) returning `Vec<Vec<HighlightedSpan>>` (NifMap with `content`, `fg`/`bg` as `Option<(u8, u8, u8)>`, plus `bold`/`italic`/`underlined` flags). `ExRatatui.CodeBlock.resolve_theme/1` is the canonical theme-atom resolver used by both the widget encoder and the helper — single source of truth. `ExRatatui.CodeBlock.from_native/1` is a documented conversion seam for callers using `Native.highlight_code/3` directly (e.g. hot loops reusing the same theme).

- **`[:ex_ratatui, :code_block, :highlight]` telemetry span.** Each `ExRatatui.CodeBlock.highlight/3` call emits start + stop via `:telemetry.span/3` with `language` (string or `nil`), `theme` (resolved syntect name), and `bytes` (source byte size); the stop event adds `line_count`. Mirrors the `[:ex_ratatui, :image, :decode]` span shape.

- **Shared `widgets::highlighter` Rust module.** `OnceLock`-cached `SyntaxSet` (`load_defaults_newlines`) + `ThemeSet` (`load_defaults`), `lines_for(code, language, theme)` returning `Vec<Line<'static>>`, `theme_bg(theme)` for the emphasis-color base. The ~25-line syntect→ratatui style/color/modifier translation is inlined (MIT-attributed in the module header) because the existing `syntect-tui` adapter is pinned to older ratatui versions (0.28/0.29) and we're on 0.30.

- **`examples/code_block_demo.exs`.** Interactive viewer that cycles through all seven themes and five sample languages (Rust, Python, Ruby, JavaScript, JSON), toggles the line-number gutter, and toggles emphasis on lines 3..5. Status panel echoes the active config live.

- **Cheatsheet entry** under `Text & content` next to BigText, and a new `"Widgets: Code"` ex_doc group covering `ExRatatui.CodeBlock` + `ExRatatui.Widgets.CodeBlock`.

- **Bundled Elixir syntax.** `native/ex_ratatui/syntaxes/Elixir.sublime-syntax` is vendored from [elixir-editors/elixir-sublime-syntax](https://github.com/elixir-editors/elixir-sublime-syntax) (MIT, copyright Po Chen — LICENSE alongside) and added to syntect's `SyntaxSet` at startup via `into_builder()` → `SyntaxDefinition::load_from_str(include_str!(...))` → `.add()` → `.build()`. `language: "elixir"` now produces real per-token highlighting (`defmodule`/`do`/`end` as keywords, atoms, strings, sigils — six distinct fg colors on a typical snippet under base16-ocean.dark). Adds ~80 KB to the binary. Other BEAM languages: Erlang ships in syntect's defaults; **EEx / HEEx / Surface are not yet bundled** — same approach can extend to them when needed.

- **Known limitation: `ExRatatui.Widgets.Markdown` fenced code blocks still use `base16-ocean.dark`** — [tui-markdown 0.3.7](https://github.com/joshka/tui-widgets/tree/main/tui-markdown) hardcodes the syntect theme internally and does not expose it through its public API. A `:code_theme` knob on the Markdown widget depends on upstream cooperation and is out of scope for this release; users who need themed fenced blocks today can pre-extract the source and render via `CodeBlock` directly.

- **`ExRatatui.Widgets.BigText` — oversized 8×8 pixel text for slide titles and banners.** Drop-in widget backed by [tui-big-text 0.8.4](https://github.com/ratatui/tui-widgets/tree/main/tui-big-text); each character is rasterised through the `font8x8` bitmap font. `ExRatatui.BigText.new/2` coerces text-like input through the shared text-coercion path (binary / `%Span{}` / `%Line{}` / `%Text{}` / homogeneous lists), validates `:pixel_size` and `:alignment`, and merges any outer `%Text{}` style underneath the widget's own. Eight `pixel_size` densities cover the full upstream variant set: `:full` (default — 1 cell per pixel, 8 rows tall), `:half_height`, `:half_width`, `:quadrant`, `:third_height`, `:sextant`, `:quarter_height`, `:octant` (1 row × half cols). Composes with `Block`, `Popup`, and `WidgetList` like every other widget. Adds one new widget type (`"big_text"`) to the render decoder; no new NIFs.

- **`examples/big_text_demo.exs`.** Interactive viewer that cycles every `pixel_size`, three alignments, six colors, and four sample slide titles at runtime. Status panel echoes the active settings live. Helpful when picking a variant for a real slide deck.

- **`ExRatatui.Widgets.Image` — image rendering across every transport.** Decodes PNG / JPEG / GIF / WebP / BMP bytes and renders them through [ratatui-image](https://github.com/ratatui/ratatui-image) with Kitty, Sixel, iTerm2, or Unicode halfblocks. `ExRatatui.Image.new/2` returns a stateful widget handle (`{:ok, %ExRatatui.Widgets.Image{}}`) or `{:error, {:decode_failed, msg}}`; protocol / resize mode / background are set at construction and stored on a NIF resource so re-encoding only happens when the resolved protocol or rect dimensions change. Three resize strategies: `:fit` (preserve aspect inside the rect), `:crop` (preserve aspect, fill, crop overflow), `:scale` (stretch to fill).

- **Transport-aware protocol resolution.** Each transport stamps a `TransportCaps` value the render path consults: `CellSession` forces `:halfblocks` (escape sequences can't survive cell diffing — Livebook / Kino apps that share model code with a real terminal just work); the local terminal can cache a `Picker::from_query_stdio` probe via `ExRatatui.Image.auto_local_protocol/1` so `:auto` resolves to the detected protocol with the right font size; SSH and Distributed accept an `:image_protocol` opt at start time, optionally paired with `:image_font_size` for accurate Kitty / Sixel / iTerm2 scaling (`ExRatatui.SSH.Daemon.start_link(..., image_protocol: :kitty, image_font_size: {10, 20})`, `ExRatatui.Distributed.attach(..., image_protocol: :kitty, image_font_size: {10, 20})`). Explicit per-image protocol selections at `Image.new/2` are always honored.

- **Image rendering over `ExRatatui.Distributed`.** Image widgets cross node boundaries via a snapshot path: the server runtime calls `image_snapshot/1` on each `%ExRatatui.Widgets.Image{state: ref}` in the render tree before sending the widget list over the wire (a NIF ResourceArc can't cross nodes). The client node re-decodes the bytes into a fresh `ImageResource` per draw. Snapshot wire shape is `{bytes, protocol, resize, background}`. Costs roughly the source PNG size per frame on the wire — fine for stills, watch bandwidth for animations on large images.

- **`probe_image_protocol: true` runtime opt for `mount/1`.** `ExRatatui.App` apps can opt into auto-probing the local terminal by returning `{:ok, state, probe_image_protocol: true}`. The runtime calls `ExRatatui.Image.auto_local_protocol/1` once after mount on the `:local` transport — `:auto` images then resolve to the detected protocol without the app needing access to the terminal reference. Skipped under `test_mode`. Other transports ignore the opt.

- **`ExRatatui.Image.render_size/4`.** Pure-Elixir prediction of the rendered output pixel dimensions for a given (source dims, cell area, font size, resize mode) combination. Mirrors ratatui-image's `Resize::needs_resize_pixels` + `fit_area_proportionally` byte-for-byte. Useful for status panels, layout decisions, or just understanding why `:fit` and `:crop` produce identical output when the source is smaller than the target.

- **`:background` accepts the full `t:ExRatatui.Style.color/0` shape.** Named atoms (`:red`, `:dark_gray`, …), `{:rgb, r, g, b}`, `{:indexed, n}` xterm 256-color codes, raw `{r, g, b}` tuples, and `nil` all work. Named and indexed values are converted to RGB at the Elixir boundary via the standard ANSI palette.

- **New public API surface.** `ExRatatui.Image.{new,dimensions,probe_terminal,auto_local_protocol,render_size}/{1,2,4}`, `ExRatatui.Session.{set_image_protocol,set_image_font_size}/2`, `ExRatatui.set_image_protocol/2`. Eight new NIFs: `image_new/2`, `image_dimensions/1`, `image_snapshot/1`, `image_probe_terminal/0`, `session_set_image_protocol/2`, `session_set_image_font_size/2`, `terminal_set_image_protocol/2`, `terminal_set_local_probe/3`.

- **`[:ex_ratatui, :image, :decode]` telemetry span.** Each `Image.new/2` call emits start + stop with `format` (sniffed from magic bytes — `:png` / `:jpeg` / `:gif` / `:webp` / `:bmp` / `:unknown`), `bytes`, and `width` / `height` on success. Per-render encode timing stays inside the existing `[:ex_ratatui, :render, :frame]` span.

- **Examples.** [`examples/image_demo.exs`](examples/image_demo.exs) is an interactive viewer with runtime protocol / resize toggling and a live status panel showing rendered output dimensions; supports `--ssh` and `--distributed` flags for smoke-testing those transports end-to-end. [`examples/headless_image.exs`](examples/headless_image.exs) renders an image through `CellSession` (with ANSI fg/bg per cell) for Livebook / snapshot consumers. Both accept `IMAGE_PATH` to skip the network fetch, default to `picsum.photos`, and embed a 1×1 fallback PNG for offline use.

- **[Images guide](guides/core/images.md) and cheatsheet entry.** Walks through the API, the full transport / protocol resolution table, the font-size caveat for Kitty / Sixel / iTerm2 scaling, telemetry, and known v1 limitations (no GIF animation, no SVG, no streaming decode, `Resize::Fit` doesn't upscale).

### Changed

- **Rust toolchain bumped to 1.86+** to match [ratatui-image 11.0.2](https://github.com/ratatui/ratatui-image)'s `rust-version` (edition 2024). ex_ratatui itself stays on edition 2021; precompiled binaries are unaffected — you only hit this if you build the NIF yourself with `EX_RATATUI_BUILD=1`.

- **Binary size grows by ~1.6 MB.** ratatui-image pulls in `image` (with PNG / JPEG / GIF / WebP / BMP decoders) and bundled Kitty / Sixel / iTerm2 encoders. No new system dependencies — chafa is feature-gated off, sixel uses pure-Rust `icy_sixel`.

### Fixed

- **Precompiled musl NIFs now load under musl runtimes.** `native/ex_ratatui/.cargo/config.toml`'s `x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl` targets now pass `-C link-arg=-static-libgcc` alongside the existing `target-feature=-crt-static`. Without it the NIF `.so` linked against the build host's glibc `libgcc_s.so.1` and the musl loader on the consumer side refused it. Alpine and other musl-libc deploys can now consume the precompiled artifact directly — no source rebuild required.

## [0.9.0] - 2026-05-7

### Added

- **Property-based tests for the `:intents` runtime opt.** New `test/ex_ratatui/property/intents_property_test.exs` (`async: true`) with two properties under the 4-tuple `{:cell_session, cs, cell_writer_fn, intent_writer_fn}` transport tag: (1) for any mount-intent list and any sequence of `handle_info`-supplied batches, the writer receives every intent in concat order with no reordering, drops, or extras; (2) empty `intents: []` batches never fire on the writer regardless of how many sequential empty handle_info calls a TUI makes. Complements the existing scenario unit tests in `ExRatatui.Server.IntentsTest` (mount-time, handle_event, handle_info, stop-with-intent, drop-without-writer, shape validation) — together they pin the full intent contract. Reuses the existing `ExRatatui.Test.ServerApps.Intents` fixture.

- **Documented `:intents` runtime opt across the public surface.** `ExRatatui.App`'s moduledoc now has a dedicated **Runtime opts** section listing every key (`:commands`, `:intents`, `:render?`, `:trace?`) with types, defaults, scope (callback vs reducer), and the "intents from `{:stop, ...}` fire before the server exits" guarantee. The `t:callback_opts/0` typedoc points at it; a new `t:intent/0` typedoc names the opaque-term contract. The `c:ExRatatui.App.handle_event/2` and `c:ExRatatui.App.handle_info/2` callback typespecs now include the `{:noreply | :stop, state, callback_opts}` 3-tuple variants — they were always accepted by the runtime but the typespecs declared only the 2-tuple shape, hiding the feature from Dialyzer and HexDocs. Their `@doc` strings now point at the [Runtime opts](`ExRatatui.App#module-runtime-opts`) section. The [Callback Runtime guide](guides/runtimes/callback_runtime.md) has a new **Runtime opts** section between `handle_info/2` and Error Handling. The [Reducer Runtime guide](guides/runtimes/reducer_runtime.md)'s existing **Runtime Options** table grew an `intents:` row with a follow-up [Intents](guides/runtimes/reducer_runtime.md#intents) subsection that names the consumer-defined vocabulary contract and the transport-portability story. The [Cell Sessions guide](guides/transports/cell_session.md) gained a **Driving an `ExRatatui.App` over a CellSession** section walking through the 3-tuple vs 4-tuple transport shapes, sample `cell_writer_fn` and `intent_writer_fn` definitions, and the lifecycle the runtime drives. End-user code is unchanged; this is documentation of the existing feature.

- **`ExRatatui.CellSession` — non-terminal rendering primitive** — sibling of `ExRatatui.Session` for consumers that aren't terminals (Phoenix LiveView painting `<span>` cells, embedded framebuffers, screenshot tools, headless tests). Backed by ratatui's `TestBackend`, it exposes the cell buffer directly instead of ANSI bytes. Same widget tree, input parser, and `draw/2` / `resize/3` / `feed_input/2` / `close/1` lifecycle as `Session`; the only API divergence is `take_output/1` being replaced by `take_cells/1` (full snapshot) and `take_cells_diff/1` (cells that changed since the last diff call). Cells are `%{row, col, symbol, fg, bg, modifiers, skip}` in row-major order, with colors and modifiers using the same `ExRatatui.Style` vocabulary as the rest of the library. `take_cells_diff/1` returns a full payload on its first call, after `resize/3`, and after reconstruction; otherwise only cells that differ structurally. Adds 9 NIFs, the `ExRatatui.CellSession{,.Cell,.Snapshot,.Diff}` modules, a [Rendering to Non-Terminal Surfaces guide](guides/transports/cell_session.md), and a headless [`cell_dump.exs`](examples/cell_dump.exs) example.

- **`:intents` runtime opt + `{:cell_session, cs, cell_writer_fn, intent_writer_fn}` 4-tuple transport tag** — `ExRatatui.App` callbacks can now return `{:ok, state, intents: [...]}` from `mount/1` and `{:noreply | :stop, state, intents: [...]}` from `handle_event/2` / `handle_info/2`. Intents are opaque to ex_ratatui — they're forwarded verbatim to the transport's `intent_writer_fn` (the optional 4th element of the cell_session transport tag) in the order they were emitted. `phoenix_ex_ratatui` consumes this to dispatch inter-page navigation (`{:navigate, "/path"}` → `push_navigate`, `{:patch, "/path"}` → `push_patch`, `{:redirect, "/url"}` → `redirect`); other consumers can define their own intent vocabulary. Transports that don't supply an intent writer (the existing 3-tuple cell_session shape, plus `:local` / `:session` / `:distributed_server`) silently drop intents — apps stay portable across transports. Intents from `{:stop, state, intents: ...}` transitions fire BEFORE the server exits, so a TUI can return `{:stop, state, intents: [{:redirect, "/login"}]}` and trust the redirect reaches the consumer before the linked-server EXIT propagates.

- **`{:cell_session, cell_session, cell_writer_fn}` Server transport tag** — ExRatatui.Server now accepts a fourth `:transport` shape (alongside `:local`, `:session`, and `:distributed_server`) that drives an `ExRatatui.App` against a `CellSession` instead of a byte-stream `Session`. On every render the Server calls `CellSession.draw/2`, then `CellSession.take_cells_diff/1`, then hands the resulting `%CellSession.Diff{}` to the user-supplied `cell_writer_fn` — same call shape as the byte-stream `:session` transport, just a different payload type. `ExRatatui.Transport.start_server/1` accepts the new shape unchanged via the `t:server_transport/0` union; the `t:cell_writer_fn/0` type lives next to the existing `t:writer_fn/0`. Mount opts are augmented identically to the byte-stream path: `opts[:transport] = :cell_session`, `opts[:width]` / `opts[:height]` populated from `CellSession.size/1`. Telemetry mirrors the existing taxonomy: `[:ex_ratatui, :transport, :connect]` and `[:ex_ratatui, :session, :lifecycle, :open]` fire on init with `transport: :cell_session`; `[:ex_ratatui, :session, :lifecycle, :close]` and `[:ex_ratatui, :transport, :disconnect]` fire on `terminate/2`. Resize semantics match `:session` exactly — the transport must call `CellSession.resize/3` before forwarding `{:ex_ratatui_resize, w, h}` to the Server, then the Server updates the cached size and dispatches a `%Event.Resize{}` to the App; the next render's diff payload after a resize is always full (prior baseline at the old area is no longer comparable).

## [0.8.2] - 2026-04-29

### Fixed

- **`%Event.Resize{}` now reaches `handle_event/2` over byte-stream transports** — when the runtime ran over a byte-stream transport (`:session` for SSH / Kino / custom TCP, `:distributed_server` for distribution), the `{:ex_ratatui_resize, w, h}` message synthesized by `ExRatatui.Transport.ByteStream` was intercepted by the Server's own `handle_info/2` clause: it updated the cached `width` / `height` and re-rendered, but never dispatched a `%Event.Resize{}` to the App. The local-tty path delivered Resize through the polling event loop, so an App that worked when run over the real terminal would silently miss resize events the moment it was supervised over SSH, distribution, or a Livebook notebook. The Server now updates its cached size first (so the follow-up render sees the new dims) and then routes the resize through `dispatch_event/2`, giving the App's `handle_event/2` exactly the same `%Event.Resize{width: w, height: h}` it would see on local tty. Apps that only had a fall-through `handle_event(_, state)` clause are unaffected; apps that explicitly track terminal size in their own state can now do so over every transport. The two transport tests (`session_transport_test.exs`, `distributed_transport_test.exs`) were updated to assert App delivery in addition to the re-render

## [0.8.1] - 2026-04-27

### Added

- **Telemetry instrumentation** ([#56](https://github.com/mcass19/ex_ratatui/issues/56)) — new `ExRatatui.Telemetry` module emits `:telemetry` events across the runtime so apps can plug in logging, metrics, or OpenTelemetry tracing without forking the server. Five span events (`:start` / `:stop` / `:exception`) wrap the costly stages: `[:ex_ratatui, :runtime, :init]` around `mount/1`, `[:ex_ratatui, :runtime, :event]` around terminal-input `handle_event/2`, `[:ex_ratatui, :runtime, :update]` around info-message `handle_info/2` (subscriptions, async results, user messages), `[:ex_ratatui, :render, :frame]` around the build+draw cycle (adds `:widget_count` to stop metadata), and `[:ex_ratatui, :transport, :connect]` around local/SSH/distributed handshakes. Four single events fire for point-in-time facts: `[:ex_ratatui, :session, :lifecycle, :open]` when a session-backed runtime adopts a session (carries `:width` / `:height`), `[:ex_ratatui, :session, :lifecycle, :close]` when it releases the session (carries `:reason`; fires exactly once per session even when the transport's own teardown defensively closes the same ref afterwards), `[:ex_ratatui, :render, :dropped]` on draw errors (with a TODO placeholder for future frame-skip backpressure), and `[:ex_ratatui, :transport, :disconnect]` on server teardown. Every event carries `:mod` and `:transport` in its metadata. `ExRatatui.Telemetry.span/3` is a thin helper that prefixes events with `:ex_ratatui` and forwards start metadata to stop; `execute/3` does the same for single events and auto-adds `:system_time`. `attach_default_logger/1` / `detach_default_logger/0` ship a handler that logs every event at a configurable level. New [Telemetry guide](guides/internals/telemetry.md) walks through the full event catalogue, a `Telemetry.Metrics` example, and an `opentelemetry_telemetry` wiring snippet. Added `{:telemetry, "~> 1.0"}` as an explicit dependency and to `extra_applications` so the handler registry is available on every node (including peers in distributed tests)
- **Transport behaviour** — new `ExRatatui.Transport` module documents the protocol between the runtime server and the processes that carry I/O for a running `ExRatatui.App`. Declares the `server_transport`, `writer_fn`, and `to_server` typespecs, plus one optional `child_spec/1` callback and a public `start_server/1` entrypoint for custom transports to boot the runtime without depending on internal modules. `ExRatatui.SSH`, `ExRatatui.SSH.Daemon`, and `ExRatatui.Distributed.Listener` all adopt the behaviour. New `ExRatatui.Transport.ByteStream` helper packages the byte-pump pattern (`forward_input/3`, `forward_resize/4`) so any byte-oriented transport — SSH today, Kino/Livebook next, a custom TCP bridge — can plug in without reimplementing event dispatch or Resize absorption. `ExRatatui.SSH` now delegates to `ByteStream` instead of hand-rolling the loop. New [Custom Transports guide](guides/transports/custom_transports.md) walks through the contract and a working TCP example covering separation of acceptor and per-connection worker (so the listener survives across disconnects and serves concurrent clients), the alt-screen enter/leave sequences, runtime-server monitoring, and the raw-mode client requirement (`stty raw -echo; nc …; stty sane`) that plain TCP needs since it has no equivalent of SSH's PTY negotiation
- **Property-based test pass over the recently-added surface** — five new files under `test/ex_ratatui/property/` covering the modules introduced by the telemetry + transport-behaviour work, plus older surface that previously lacked sweeping coverage. `session_input_property_test.exs` proves `ExRatatui.Session.feed_input/2`'s **byte stitchability** (splitting any byte stream at any boundary, including byte-by-byte, yields the same event sequence) along with shape invariants for printable bytes, bare ESC, and arrow keys. `byte_stream_property_test.exs` covers `ExRatatui.Transport.ByteStream.forward_input/3`'s contract: no `%Event.Resize{}` ever leaks as a regular event, every parsed event is delivered in order, and `forward_resize/4` always emits an `:ex_ratatui_resize` notification. `bridge_property_test.exs` covers `Bridge.encode_commands!/1`'s list-level contract — length / order preservation, `{map, map}` shape, rect coordinate passthrough, and `ArgumentError` on malformed entries — across structurally simple widgets (Paragraph, Block, Clear, Gauge, Throbber). `text_encode_property_test.exs` covers `Text.Encode.to_wire_text!/to_wire_line!` line/span count and content preservation, alignment serialization, and per-line agreement between the two encoders. `normalize_property_test.exs` covers `Subscription.normalize/1` and `Command.normalize/1` idempotence, leaf-count preservation across nested batches, order preservation, and refusal of garbage shapes. The exhaustive per-widget validation property suite (one shape generator per widget × known-malformed shapes raising `ArgumentError`, ~22 widgets) is intentionally deferred — the structural invariants above are uniform across widgets, so the next pass is a per-widget effort rather than a generic one

### Changed

- **Internal `:ssh` transport tag renamed to `:session`** — the Server's internal transport tag always described "generic byte-stream session"; SSH just happened to be the first user. The new name makes room for other byte-stream transports (Kino, custom TCP) to share the same runtime without impersonating SSH. User-facing routing shorthand is untouched: `{MyApp, transport: :ssh}` still routes to `SSH.Daemon`. Affected surfaces: `Runtime.snapshot/1` `.transport` now returns `:session` for byte-stream sessions (was `:ssh`); telemetry metadata `%{transport: _}` on `[:runtime, :init]`, `[:transport, :connect]`, etc. is now `:session` on byte-stream events; `mount(opts)[:transport]` is now `:session` for SSH apps (was `:ssh`). If your app branches on `opts[:transport]` to detect SSH specifically, switch to a different signal (you control the `{MyApp, transport: :ssh}` line in your own supervision tree)


## [0.8.0] - 2026-04-21

### Added

- **Chart widget** — new `ExRatatui.Widgets.Chart` struct plus `Chart.Dataset` and `Chart.Axis` companions wrap ratatui's `Chart` for x/y line, scatter, and bar plots with axes, labels, legend, and multi-series support. Each `%Dataset{}` carries a `:name` (shown in the legend), a list of `{x, y}` numeric tuples in `:data`, plus its own `:marker` (`:braille` / `:dot` / `:block` / `:bar` / `:half_block`), `:graph_type` (`:line` / `:scatter` / `:bar`), and `:style`, so a single chart can mix line and scatter overlays. The required `:x_axis` / `:y_axis` are `%Axis{}` structs with `:bounds` (`{min, max}` numeric tuple), optional tick `:labels` (string / `%Span{}` / `%Line{}`), `:title`, `:style`, and `:labels_alignment` (`:left` / `:center` / `:right`). `:legend_position` accepts `:top`, `:top_left`, `:top_right` (default), `:bottom`, `:bottom_left`, `:bottom_right`, `:left`, `:right`, or `nil` to hide the legend entirely. `:hidden_legend_constraints` takes a `{width_constraint, height_constraint}` pair using the same shapes as `ExRatatui.Layout` (`:length` / `:percentage` / `:ratio` / `:min` / `:max` / `:fill`) — the legend is hidden whenever its rendered size would exceed those bounds against the chart area. `:block` wraps the chart in a framed `Block`. Missing axes, non-list `:datasets`, non-`%Dataset{}` entries, malformed data points, non-numeric coordinates, unknown markers, unknown `:graph_type`s, unknown `:legend_position`s, malformed `:bounds`, malformed `:hidden_legend_constraints`, and unknown `:labels_alignment` values raise `ArgumentError` at the bridge boundary. See the [widget cheatsheet](guides/cheatsheets/widgets.cheatmd) for examples
- **Canvas widget** ([#30](https://github.com/mcass19/ex_ratatui/issues/30)) — new `ExRatatui.Widgets.Canvas` struct and six shape structs (`Canvas.Line`, `Canvas.Rectangle`, `Canvas.Circle`, `Canvas.Points`, `Canvas.Map`, `Canvas.Label`) wrap ratatui's `Canvas` for 2D plotting. Shapes live in a virtual coordinate space defined by `:x_bounds` / `:y_bounds` (both `{min, max}` tuples with `min <= max`) and are rasterized onto cells via `:marker` — `:braille` (default), `:dot`, `:block`, `:bar`, or `:half_block`. `Rectangle` draws an outline anchored at its bottom-left corner, `Circle` draws an outline centered on `{x, y}`, `Points` plots a list of `{x, y}` tuples, `Map` paints the world's coastlines at `:low` or `:high` resolution (pair with `{-180, 180}` × `{-90, 90}` bounds), and `Label` writes a styled text annotation at the given canvas-space coordinate. Every drawable shape takes a plain `Color.t()` rather than a `Style` — canvas pixels sample individual cells, so text modifiers don't apply; `Label` uses the color as the text foreground. `:background_color` fills the area, and `:block` wraps the canvas in a framed `Block`. Non-tuple bounds, inverted bounds, unknown markers, unknown map resolutions, missing required shape fields, negative `width` / `height` / `radius`, non-string `Label.text`, malformed `Points.coords` entries, and unknown shape structs all raise `ArgumentError` at the bridge boundary. See the [widget cheatsheet](guides/cheatsheets/widgets.cheatmd) for examples
- **Calendar widget** ([#31](https://github.com/mcass19/ex_ratatui/issues/31)) — new `ExRatatui.Widgets.Calendar` struct renders ratatui's `Monthly` calendar. `:display_date` is a native `%Date{}` that drives which month is shown and which day is highlighted. `:events` accepts either a list of `{%Date{}, %Style{}}` tuples or a `%{Date => Style}` map — map entries with a `nil` value are skipped so toggling individual days stays ergonomic. `:show_month_header` and `:show_weekdays_header` (booleans, default `true`) toggle the two header rows, with independent `:header_style` / `:weekday_style` overrides. Set `:show_surrounding` to a `%Style{}` to bleed the previous/next month into empty grid cells; leave it `nil` to hide them. `:default_style` paints unstyled days, and `:block` wraps the widget in a framed `Block`. Non-`Date` `:display_date`, non-boolean header toggles, and malformed event entries raise `ArgumentError` at the bridge boundary. See the [widget cheatsheet](guides/cheatsheets/widgets.cheatmd) for examples
- **Sparkline widget** ([#27](https://github.com/mcass19/ex_ratatui/issues/27)) — new `ExRatatui.Widgets.Sparkline` struct renders ratatui's `Sparkline`, a compact single-line bar chart for streaming or time-series data. `:data` is a list of non-negative integers with `nil` entries representing missing samples; set `:max` to a positive integer or leave `nil` to auto-scale. Choose a rendering style via `:bar_set` — `:nine_levels` for smooth gradients, `:three_levels` for low-density glyphs, or a non-empty list of strings that's proportionally mapped across ratatui's nine density slots. Direction (`:left_to_right` / `:right_to_left`), absent-value symbol and style, chart-wide `:style`, and `:block` are all configurable. Floats, negative values, non-list data, unknown bar-set atoms, and empty custom lists raise `ArgumentError` at the bridge boundary. See the [widget cheatsheet](guides/cheatsheets/widgets.cheatmd) for examples
- **BarChart widget** ([#23](https://github.com/mcass19/ex_ratatui/issues/23)) — new `ExRatatui.Widgets.BarChart`, `ExRatatui.Widgets.Bar`, and `ExRatatui.Widgets.BarGroup` structs render ratatui's `BarChart` in either `:vertical` or `:horizontal` orientation. Each `%Bar{}` carries a `:label`, non-negative integer `:value`, optional per-bar `:style` that overrides the chart-wide `:bar_style`, and an optional `:text_value` to replace the numeric readout. Chart-level fields include `:data` (single anonymous group of bars), `:groups` (list of `%BarGroup{}` for side-by-side clusters with shared captions), `:bar_width`, `:bar_gap`, `:group_gap` (cells between adjacent clusters), `:bar_style`, `:value_style`, `:label_style`, `:max` (nil auto-scales to the largest value), `:direction`, and `:block`. Set either `:data` or `:groups`. Floats, negative values, non-list `:groups`, non-`%BarGroup{}` entries, non-string group labels, and negative `:group_gap` raise `ArgumentError` at the bridge boundary. See the [widget cheatsheet](guides/cheatsheets/widgets.cheatmd) for examples
- **Focus management** ([#48](https://github.com/mcass19/ex_ratatui/issues/48)) — new `ExRatatui.Focus` struct for multi-panel apps. Declare an ordered ring of focusable IDs with `Focus.new/2`, route every key event through `Focus.handle_key/2`, and pattern-match on `Focus.current/1` to dispatch. Tab / Shift+Tab / `back_tab` are consumed by default; `:next_keys` / `:prev_keys` accept `%Event.Key{}` entries to override (`:kind` ignored, modifiers compared as a set). `Focus.focused?/2` drives border styling without `Focus` ever touching widget structs. Pure Elixir, no Rust changes. The new "Focus management" section in [Building UIs](guides/core/building_uis.md#focus-management) walks through the caller pattern
- **Widget protocol** ([#24](https://github.com/mcass19/ex_ratatui/issues/24)) — new `ExRatatui.Widget` protocol lets you build composite widgets in pure Elixir by implementing `render/2` on your own struct. The Bridge flattens custom widgets into primitive `{widget, rect}` tuples recursively (with a 32-level depth cap and argument validation) before encoding, so `ExRatatui.draw/2` accepts primitive and custom widgets interchangeably at the top level. Custom widgets inside `Popup.content` / `WidgetList.items` are not supported yet. The public `widget()` type splits into `primitive_widget()` (built-ins, unchanged) and `widget()` (primitive or any struct implementing the protocol); the new [Custom Widgets](guides/core/custom_widgets.md) guide walks through the API. Protocol consolidation is now limited to `:prod`, so test-time `defimpl` blocks (and your own tests of custom widgets) work without fuss
- **Rich text primitives** ([#26](https://github.com/mcass19/ex_ratatui/issues/26)) — new `ExRatatui.Text.Span` and `ExRatatui.Text.Line` structs let text-bearing widget fields carry per-span colors and modifiers instead of a single style for the entire string. `Paragraph.text`, `List.items`, `Table.rows`/`Table.header`, `Tabs.titles`, and `Block.title` now accept any mix of `String.t()`, `%Span{}`, `%Line{}`, or `[%Span{}]`. Plain strings continue to work on every field; fields that are semantically single-line (table cells, tab titles, block titles) raise on strings containing embedded newlines. The new "Rich Text" section in [Building UIs](guides/core/building_uis.md#rich-text) walks through the API

### Fixed

- **TextInput cursor invisible at end of double-width input** ([#45](https://github.com/mcass19/ex_ratatui/issues/45)) — when a `TextInput` contained CJK or other double-width characters that overflowed the widget's display width, moving the cursor to the end made it disappear. Viewport scrolling and span construction tracked positions in char counts but the widget's display width is measured in terminal cells, so wide chars consumed twice their accounted-for space and the trailing cursor span was truncated. Both the viewport adjustment and the rendered spans are now cell-aware via the `unicode-width` crate

### Changed

- **Documentation expanded.** Five new guides ship in `guides/`: [Getting Started](guides/introduction/getting_started.md) walks `mix new` → supervised todo app with `TextInput` + `List` + manual focus; [State Machine Patterns](guides/runtimes/state_machines.md) covers mode-atom dispatch, screen stacks, modals via `Popup`, multi-screen transitions, and sibling-GenServer escape hatches; [Testing](guides/internals/testing.md) documents the headless backend, `test_mode`, `Runtime.inject_event/2`, and three assertion patterns (snapshot, `test_pid`, `:sys.get_state`); [Debugging](guides/internals/debugging.md) covers `Runtime.snapshot/1`, `enable_trace/2` events, buffer-inspection-as-dev-tool, common errors (`terminal_init_failed`, garbled output, SSH `-t`, `mix run` stdin), and Rust NIF rebuilds; [Performance](guides/internals/performance.md) covers the render loop, `render?: false`, keeping `render/2` cheap, large trees, poll-interval tuning, subscription cost, async effects, and timing with `:timer.tc` + traces. The widgets cheatsheet was rewritten as task-grouped columns (Styles, Layout, Text, Lists, Progress, Input, Charts, Containers, Calendar) using `{: .col-2}` annotations for scan-ability. A new `examples/README.md` catalogs all 12 examples with SSH and Erlang-distribution one-liners. The top-level README dropped its Learning Path, Testing sample, and Troubleshooting sections (all absorbed by the new guides) and trimmed the Examples table to two (`hello_world` + `counter_app`), now pointing to the examples catalog. Hex sidebar reordered: onboarding → concepts → patterns → ops → cheatsheet
- **Test suite expanded.** New coverage: property-based invariants for `Layout.split/3`, style encoding, text coercion, `Focus` ring semantics, and `decode_event/1` round-tripping key/mouse/resize tuples via `stream_data`; unicode and emoji rendering across CJK, combining marks, ZWJ sequences, and BMP/SMP emoji on every text-bearing widget; stress tests for 2 000-widget scenes, 1 000 redraws, and 1×1 / 500×500 terminals; cross-transport parity tests proving the same `App` module produces identical widget trees under local, SSH, and Erlang distribution; raw-example smoke tests for `system_monitor` (App-based) and `chat_interface` (raw `ExRatatui.run/1` loop). Distributed integration now also exercises Chart, grouped BarChart, and Canvas with a `Map` shape to catch any future NIF-field regression across node boundaries. Coverage remains at 100% across all 55 modules
- **Test layout mirrors `lib/`.** `test/ex_ratatui/widgets_test.exs` was split into per-widget files under `test/ex_ratatui/widgets/`, one-for-one with `lib/ex_ratatui/widgets/`. Cross-cutting integration tests (cross-transport parity, unicode rendering, stress, focus integration, full-stack rendering) now live under `test/integration/`. `server_runtime_test.exs` was renamed to `runtime_test.exs` and `test_backend_test.exs` folded into `terminal_test.exs` to match the modules they cover. `server_test.exs` was further split by transport: SSH and distributed unit tests now live in `test/ex_ratatui/server/ssh_transport_test.exs` and `test/ex_ratatui/server/distributed_transport_test.exs`, each organized under `describe` blocks for lifecycle, message handling, reducer support, and helpers. Duplicated fixture apps across the three server test files were consolidated into `ExRatatui.Test.ServerApps` (`Echo`, `StopOnAnyEvent`, `FailingMount`) under `test/support/`, and SSH test helpers into `ExRatatui.Test.SshHelper`
- **CI hardening.** The `distributed` and `slow` jobs merged into a single `extras` job that runs both tag filters sequentially, saving a runner. The lint matrix now runs `mix xref graph --format cycles --fail-above 0` to catch dependency cycles at CI time. Doctests added to `ExRatatui.Command` and `ExRatatui.Subscription` for the reducer side-effect helpers
- **API polish.** `ExRatatui` moduledoc now documents the error-handling convention: programmer errors raise `ArgumentError`, runtime/I/O failures return `{:error, reason}`. `ExRatatui.Command.async/2` docs now enumerate the mapper's error shapes and include an example. `TextInput` and `Textarea` moduledocs note their `:state` references are node-local NIF resources that must not be serialized, compared, or sent across distribution. The `Bridge` module is hidden from HexDocs (`@moduledoc false`) since it's internal to the NIF boundary
- **Shutdown robustness.** The internal server's `terminate/2` now cancels any armed subscription timers across all three transports, so pending ticks can't be delivered to a supervisor-restarted process carrying a stale mailbox

## [0.7.1] - 2026-04-13

### Fixed

- **SSH bare Esc key not detected** — VTE's state machine swallows `0x1B` as the start of an escape sequence, so a bare Esc press over SSH produced no event. The SSH transport now schedules a 50 ms timeout after a lone `0x1B` with no follow-up bytes; if the timer fires it resets the parser and dispatches a synthetic `%Event.Key{code: "esc"}` press. Follow-up bytes (the normal case for multi-byte sequences like arrow keys) cancel the timer before it fires. Added `Session.reset_parser/1` and its backing `session_reset_parser` NIF
- **Distributed transport crashes on stateful widgets** — `TextInput` and `Textarea` store their mutable state in NIF resource references that cannot cross BEAM node boundaries via Erlang distribution. The distributed server now snapshots stateful widget state into plain tuples before sending, and the Rust decoder reconstructs temporary resources from the snapshot on the client node. Stateless widgets are unaffected. Added `text_input_snapshot` and `textarea_snapshot` NIFs

## [0.7.0] - 2026-04-13

### Added

- **Reducer runtime** for `ExRatatui.App` via `use ExRatatui.App, runtime: :reducer`. Reducer apps implement `init/1`, `render/2`, and `update/2`, receive terminal input as `{:event, event}`, mailbox messages as `{:info, msg}`, and can declare subscriptions with `subscriptions/1`
- `ExRatatui.Command` — reducer side-effect helpers for immediate messages, delayed messages, async work, and batched command execution
- `ExRatatui.Subscription` — reducer timer/subscription helpers for interval and one-shot self-messages reconciled by stable `id`
- `ExRatatui.Runtime` — runtime inspection helpers exposing snapshots, trace events, and trace enable/disable controls for supervised TUI processes
- `ExRatatui.Runtime.inject_event/2` — deterministic synthetic event injection for supervised apps under `test_mode`
- Example: `examples/reducer_counter_app.exs` — simple reducer-driven counter showing `update/2` and `subscriptions/1`

### Changed

- `ExRatatui.App` now supports two runtime styles: the existing callback runtime and the new reducer runtime selected with `runtime: :reducer`
- The internal server now supports reducer runtime options for commands, render suppression, trace state, runtime snapshots, async command tracking, and subscription reconciliation
- Render-command encoding moved into a shared internal bridge, making `ExRatatui.draw/2` and `ExRatatui.Session.draw/2` share one validation and encoding path
- Native render-command decoding was refactored into reusable helpers in `native/ex_ratatui/src/decode.rs` and shared between local terminal rendering and session rendering
- Bumped `ratatui-textarea` Rust dependency from 0.8 to 0.9
- `credo` dependency restricted to `:dev` environment only

### Fixed

- New subscriptions now store their timer reference correctly instead of keeping the `{timer_ref, token}` tuple in the `timer_ref` field, which broke timer cancellation/rearming paths in the reducer runtime
- Async command mappers are now wrapped the same way as async functions, so mapper exceptions/exits return structured error tuples and `active_async_commands` bookkeeping is always decremented
- The `mount/1` callback contract now includes the supported `{:ok, state, callback_opts}` form, which keeps reducer-style startup shims aligned with Dialyzer and the runtime's actual behavior
- Invalid reducer/runtime payloads and malformed render commands now fail earlier with clearer Elixir-side or Rust-side validation errors
- **Parallel cold compile crash** — the NIF bridge no longer loads its NIF via `@on_load` during dependency compilation. Precompiled/source artifacts are still prepared at compile time, but the NIF now loads lazily on first use, which stops isolated compiler VMs from crashing under parallel cold compiles on this host
- **`test_mode` input flake** — local supervised apps and distributed attach clients no longer poll the real terminal while running headless tests, which removes ambient crossterm events from async test runs and stops spurious renders like the `render?: false` reducer flake
- **SSH `auto_host_key` bootstrap** — host-key generation now recreates the parent `<priv_dir>/ssh/` directory immediately before writing the key, so first boot succeeds even if the app's priv tree was absent or cleaned between runs

### Docs

- Extracted runtime and widget content from README into dedicated guides: `guides/callback_runtime.md`, `guides/reducer_runtime.md`, and `guides/building_uis.md`
- Added widget cheatsheet: `guides/cheatsheets/widgets.cheatmd`
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

### Added

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

- `test_mode` now means fully headless local runtime behaviour: it disables live terminal input polling on both the server and `Distributed.Client`, and runtime snapshots expose whether polling is enabled
- Server event and resize handlers are now shared between `:ssh` and `:distributed_server` transports
- `ExRatatui.App` `dispatch_start/1` routes `:distributed` to `ExRatatui.Distributed.Listener.start_link/1`
- **`WidgetList` `scroll_offset` is now row-based** — previously `scroll_offset` skipped whole items by index; it now skips rows of content. To scroll to a specific item, sum the heights of all preceding items. Items partially above the viewport are clipped at the row level, enabling smooth pixel-row scrolling for chat histories and similar variable-height lists. This is a **breaking change** for callers that relied on the item-index interpretation

  **Migration:** If you set `scroll_offset` to an item index (e.g., `scroll_offset: selected`), replace it with the cumulative row height of preceding items. For example, if all items have height 3: `scroll_offset: selected * 3`. For variable-height items, sum their heights: `scroll_offset: items |> Enum.take(selected) |> Enum.map(&elem(&1, 1)) |> Enum.sum()`

### Fixed

- **`WidgetList` partial-item clipping** — items straddling the top edge of the viewport are now correctly rendered via an off-screen buffer blit instead of being skipped entirely

## [0.6.1] - 2026-04-09

### Fixed

- **SSH subsystem dispatch** — `ssh host -s Elixir.MyApp.TUI` (and `ExRatatui.SSH.subsystem/1` under `nerves_ssh`) would hang forever instead of rendering. The channel handler was waiting for a `{:ssh_cm, _, {:subsystem, ...}}` message inside `handle_ssh_msg/2`, but OTP `:ssh` consumes that request internally when it matches a name in the daemon's `:subsystems` config — the handler only ever receives `{:ssh_channel_up, ...}`. `ExRatatui.SSH` now detects subsystem-mode dispatch (via a new `subsystem: true` flag baked into the init args by `subsystem/1` and `ExRatatui.SSH.Daemon`) and synthesizes a default 80x24 session + starts the TUI server directly from `{:ssh_channel_up, ...}`. Shell-mode startup (via `ssh_cli`) is unchanged — it still waits for `pty_req` + `shell_req` as before
- **SSH subsystem + `-t` pty_req races** — when a client connects with `ssh -t -s Elixir.MyApp.TUI`, OTP fires `ssh_channel_up` first (we start an 80x24 session + server) and then delivers the client's `pty_req` with the real dimensions. The previous `pty_req` handler created a brand-new `Session` on every call, which left the SSH channel pointing at a session the running Server no longer rendered into. The handler now splits on `session: nil` vs `session: %Session{}` and resizes the existing session in place when one is already there, mirroring the `window_change` path
- **SSH subsystem pty-size discovery on nerves_ssh** — even with the pty_req race fixed, a subsystem TUI riding on `nerves_ssh` (or any `:ssh.daemon` that configures a default CLI handler) would stay stuck at the hardcoded 80x24 fallback instead of filling the client's real terminal. Root cause: OTP's `ssh_connection:handle_cli_msg/3` hands pty_req to the daemon's default CLI handler when the channel's user pid is still `undefined`, and then silently orphans that CLI handler the moment the subsequent subsystem request rebinds the pid to us — so the subsystem handler *never* sees pty_req on those deployments, no matter how early it arrives. `ExRatatui.SSH` now sidesteps the whole OTP path by emitting a Cursor Position Report roundtrip (`ESC[s ESC[9999;9999H ESC[6n ESC[u`) on `{:ssh_channel_up, ...}`: the client clamps the bogus cursor position to its real pty size, responds with `ESC[<row>;<col>R`, the session's ANSI input parser decodes that as a `%ExRatatui.Event.Resize{}`, and the `{:data, ...}` handler resizes the session in place + notifies the running server via `{:ex_ratatui_resize, w, h}`. Shell-mode startup is unaffected — it still reads the dimensions straight off `pty_req`
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

[Unreleased]: https://github.com/mcass19/ex_ratatui/compare/v0.10.2...HEAD
[0.10.2]: https://github.com/mcass19/ex_ratatui/compare/v0.10.1...v0.10.2
[0.10.1]: https://github.com/mcass19/ex_ratatui/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/mcass19/ex_ratatui/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/mcass19/ex_ratatui/compare/v0.8.2...v0.9.0
[0.8.2]: https://github.com/mcass19/ex_ratatui/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/mcass19/ex_ratatui/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/mcass19/ex_ratatui/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/mcass19/ex_ratatui/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/mcass19/ex_ratatui/compare/v0.6.2...v0.7.0
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
