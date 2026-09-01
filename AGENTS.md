# ExRatatui

Elixir bindings for the Rust [ratatui](https://ratatui.rs) terminal UI library, via Rustler NIFs. A library published to Hex — not an application. Widgets are plain Elixir structs (pure view descriptors) assembled each frame; rendering runs on the BEAM's DirtyIo schedulers so it never blocks application processes.

The consumer-facing API guide lives in [usage-rules.md](usage-rules.md) (shipped with the package). This file is the contributor brief.

## Architecture

- **`lib/`** — the public Elixir API:
  - **Runtimes**: `ExRatatui.run/2` (closure, scripts/one-shots), `use ExRatatui.App` (supervised LiveView-style callbacks — the default), `use ExRatatui.App, runtime: :reducer` (pure `update/2` transitions with `Command`/`Subscription` managed effects)
  - **Widgets**: structs under `ExRatatui.Widgets.*`; custom widgets implement `ExRatatui.Widget`
  - **Transports**: `:local` (with `ExRatatui.LocalInput` guarding against the BEAM `prim_tty` reader race), SSH (`ExRatatui.SSH.Daemon`), Erlang distribution (`ExRatatui.Distributed`), plus `ExRatatui.CellSession` for rendering to non-terminal surfaces
- **`native/ex_ratatui/`** — the Rust crate (ratatui + crossterm) behind the NIF. Release profile is size-tuned (strip, fat LTO, codegen-units 1), so from-source release builds are slow by design
- **Precompiled NIFs** ship via `rustler_precompiled`; the checksum file lives at the repo root
- **`guides/`** — ExDoc guides; **`examples/`** — runnable example scripts; **`priv/templates/burrito`** — packaging template

## Build

- Default `mix compile` downloads the precompiled NIF. `EX_RATATUI_BUILD=true mix compile` builds the Rust NIF from source (required for any Rust change)
- When editing Rust code: `rm -rf _build` once, then keep `EX_RATATUI_BUILD` set for every mix command — otherwise a stale NIF keeps loading silently
- `mix rust.check` runs `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` inside the crate

## Testing

- CI enforces **100% coverage** on the Elixir side (`mix test --cover`); the NIF bridge and peer-node fixtures are excluded in `mix.exs`. Tests belong in the same commit as the code they cover
- **Widgets**: headless backend via `ExRatatui.init_test_terminal/2`. **Runtime/app behaviour**: `test_mode` + `ExRatatui.Runtime.inject_event/2`, asserting on snapshots or emitted messages
- `:distributed` tests are excluded by default — run with `elixir --sname test -S mix test --include distributed`. `:slow` is reserved for heavyweight regression tests
- TTY traps: never run examples through a backgrounded `mix run`/`iex` (no TTY → fake `terminal_init_failed`), and never write tests that depend on the *absence* of a TTY — inject behaviour through seams instead

## Conventions

- Every public function gets `@doc` + `@spec` with runnable `## Examples` (doctests count toward coverage); every public module gets a `@moduledoc`
- New widgets need three things: a `@moduledoc` with field descriptions and an example, an entry in `guides/core/building_uis.md`, and an entry in `guides/cheatsheets/widgets.cheatmd`
- Every feature or behaviour change gets a CHANGELOG entry under `[Unreleased]` (Keep a Changelog groups); breaking changes include a Migration note
- Docs voice: "we" or no subject — never address the reader as "you". Guides use one physical line per paragraph; prose is never hard-wrapped at a column
- Commit subjects use `feat:`/`fix:`/`docs:`/`test:`/`refactor:`/`chore:` prefixes. `@version` bumps happen only in dedicated release commits
- Pre-PR gate: `mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix dialyzer && mix test --cover && mix rust.check`
- When the public API shape changes, update `usage-rules.md` too — downstream agents consume it
