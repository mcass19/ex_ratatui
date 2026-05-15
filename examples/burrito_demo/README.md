# burrito_demo — single-binary distribution example

Packages the `examples/counter_app.exs` TUI as a self-contained native
binary via [Burrito](https://github.com/burrito-elixir/burrito). End users
download one file, run it, and the BEAM + ex_ratatui + Rust NIF are
extracted on first launch into a per-user cache directory.

Same widget tree as the original counter script — the interesting bits are
in `mix.exs` (release config) and `lib/burrito_demo/{application,cli}.ex`
(entry point pattern).

## Prerequisites

- Erlang/Elixir matching ex_ratatui's `mix.exs`
- `zig` **exactly 0.15.2** — pinned by Burrito 1.5
- `xz` (any recent version)
- `7z` *only* for cross-building Windows targets

`mise install zig@0.15.2 && mise use -g zig@0.15.2` is the quickest path.

## Build

From this directory:

```bash
mix deps.get
MIX_ENV=prod mix release --overwrite
```

Output lands in `burrito_out/burrito_demo_linux` (~19 MB stripped, statically
linked). Other targets are wired in chunk 2.

## Run

```bash
./burrito_out/burrito_demo_linux
```

First run unpacks to `~/.local/share/.burrito/burrito_demo_*/` and re-execs.
Subsequent runs skip the unpack.

Controls match the original counter:

- `Up` / `k` — increment
- `Down` / `j` — decrement
- `q` — quit

## Clean

```bash
rm -rf _build deps burrito_out
rm -rf ~/.local/share/.burrito/burrito_demo_*
```

The cache directory is shared with other Burrito apps on the same machine,
so the `burrito_demo_*` glob is important.

## What this proves

- ex_ratatui's precompiled NIF survives the Burrito unpack/relocate cycle
  on Linux x86_64.
- The OTP `:mod` callback (`BurritoDemo.Application`) plus a `Task` calling
  `BurritoDemo.CLI.main/1` is enough to bridge Burrito's entry point into
  a TUI render loop, with `System.stop/1` for clean shutdown.

Open follow-ups tracked in `docs/dev/2026-04-23-burrito-distribution-design.md`.
