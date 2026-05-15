# burrito_demo — single-binary distribution example

Packages the `examples/counter_app.exs` TUI as a self-contained native
binary via [Burrito](https://github.com/burrito-elixir/burrito). End users
download one file, run it, and the BEAM + ex_ratatui + Rust NIF are
extracted on first launch into a per-user cache directory.

Same widget tree as the original counter script — the interesting bits are
in `mix.exs` (release config + NIF swap step) and `lib/burrito_demo/`
(entry point pattern).

## Prerequisites

`mise install` from this directory provides `zig 0.15.2` (pinned by Burrito 1.5)
and `cargo-zigbuild` (used to cross-build the NIF for Burrito's musl runtime).

One extra step that isn't a mise tool:

```bash
rustup target add x86_64-unknown-linux-musl
```

`xz` must be on `PATH` (it usually already is on Linux).

## Why we cross-build the NIF locally

Burrito's Linux payload is musl-based. ex_ratatui's published
`x86_64-unknown-linux-musl` precompiled NIF currently links `libgcc_s.so.1`
dynamically — under musl that resolves to nothing and the NIF fails to load.
The fix is `-C link-arg=-static-libgcc` in `native/ex_ratatui/.cargo/config.toml`
(landed in this branch); once a new ex_ratatui release ships the corrected
artifact, the cross-build dance below disappears and this example becomes a
plain precompiled-NIF consumer.

## Build

From this directory:

```bash
# 1. Cross-build the musl NIF locally (once per ex_ratatui code change)
( cd ../../native/ex_ratatui && cargo zigbuild --target x86_64-unknown-linux-musl --release )

# 2. Build the burrito release. The TARGET_* env vars tell rustler_precompiled
#    to resolve the musl variant; a release step in mix.exs swaps in the
#    locally-built NIF over the (broken) downloaded one.
unset EX_RATATUI_BUILD
TARGET_ARCH=x86_64 TARGET_VENDOR=unknown TARGET_OS=linux TARGET_ABI=musl \
  MIX_ENV=prod mix release --overwrite
```

Output lands at `burrito_out/burrito_demo_linux` (~17 MB stripped). The
release step prints `[burrito_demo] swapped musl NIF -> ...` confirming the
swap fired.

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

- Burrito 1.5 wraps an ex_ratatui app on Linux x86_64 end-to-end.
- The musl-cross NIF build (cargo-zigbuild + `-static-libgcc`) produces a
  self-contained `.so` that loads under Burrito's musl payload.
- The OTP `:mod` callback (`BurritoDemo.Application`) plus a `Task` calling
  `BurritoDemo.CLI.main/1` is enough to bridge Burrito's entry point into a
  TUI render loop, with `System.stop/1` for clean shutdown.

Open follow-ups tracked in `docs/dev/2026-04-23-burrito-distribution-design.md`.
