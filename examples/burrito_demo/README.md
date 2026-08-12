# burrito_demo — single-binary distribution example

Packages the `examples/basics/counter_app.exs` TUI as a self-contained native
binary via [Burrito](https://github.com/burrito-elixir/burrito). End users
download one file, run it, and the BEAM + ex_ratatui + Rust NIF are
extracted on first launch into a per-user cache directory.

Same widget tree as the original counter script — the interesting bits are
in `mix.exs` (release config) and `lib/burrito_demo/` (entry point
pattern).

For the wider story, see the
[Packaging with Burrito guide](../../guides/packaging/packaging_with_burrito.md).

## Prerequisites

`mise install` from this directory provides `zig 0.15.2` (pinned by
Burrito 1.5). `xz` must be on `PATH` (already present on Linux and
macOS).

## Build

From this directory:

```bash
mix deps.get
TARGET_ABI=musl BURRITO_TARGET=linux MIX_ENV=prod mix release --overwrite
```

`TARGET_ABI=musl` is needed only for the `linux` target — burrito's
linux wrapper uses a musl runtime, so the bundled NIF must be the musl
variant. macOS and Windows targets do not need the override.

Output lands at `burrito_out/burrito_demo_linux` (~17 MB stripped). For
`macos`, `macos_silicon`, or `windows` artifacts, run the same command
on a host matching the target OS — the bundled NIF is resolved from the
build host's triple, so cross-host releases will fail to load. The
[Burrito Demo CI workflow](../../.github/workflows/burrito_demo.yml)
shows the per-target matrix.

## Run

```bash
./burrito_out/burrito_demo_linux
```

First run unpacks to `~/.local/share/.burrito/burrito_demo_*/` and
re-execs. Subsequent runs skip the unpack.

Controls match the original counter:

- `Up` / `k` — increment
- `Down` / `j` — decrement
- `q` — quit

A `--version` flag exits without entering raw mode — useful for CI smoke
tests and the `burrito_demo.yml` workflow uses it on every push.

## Clean

```bash
rm -rf _build deps burrito_out
rm -rf ~/.local/share/.burrito/burrito_demo_*
```

The cache directory is shared with other Burrito apps on the same machine,
so the `burrito_demo_*` glob is important.

## What this proves

- ex_ratatui's precompiled NIF survives the Burrito unpack/relocate cycle
  on Linux x86_64, macOS (x86_64 and aarch64), and Windows x86_64.
- The OTP `:mod` callback (`BurritoDemo.Application`) plus a `Task`
  calling `BurritoDemo.CLI.main/1` is enough to bridge Burrito's entry
  point into a TUI render loop, with `System.stop/1` for clean shutdown.
