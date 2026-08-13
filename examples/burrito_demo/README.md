# burrito_demo — single-binary distribution example

Packages the `examples/basics/counter_app.exs` TUI as a self-contained native binary via [Burrito](https://github.com/burrito-elixir/burrito). End users download one file, run it, and the BEAM + ex_ratatui + Rust NIF are extracted on first launch into a per-user cache directory.

Same widget tree as the original counter script — the interesting bits are `mix.exs` (release config) and `lib/burrito_demo/` (entry point pattern).

For the wider story, see the [Packaging with Burrito guide](../../guides/packaging/packaging_with_burrito.md).

## Prerequisites

`mise install` from this directory provides `zig 0.16.0` (pinned by Burrito 1.6). `xz` must be on `PATH` (already present on Linux and macOS).

## Build

From this directory:

```bash
mix deps.get
TARGET_ABI=musl BURRITO_TARGET=linux MIX_ENV=prod mix release --overwrite
```

`TARGET_ABI=musl` is needed only for the `linux` target — burrito's linux wrapper uses a musl runtime, so the bundled NIF must be the musl variant. macOS and Windows targets do not need the override.

`TARGET_ABI` only chooses between *precompiled* NIFs, so it is ignored whenever the crate is built from source. With `EX_RATATUI_BUILD` exported or `:force_build` set in the `rustler_precompiled` config, the release picks up a NIF compiled against the build host's glibc no matter what `TARGET_ABI` says — prefix the command with `env -u EX_RATATUI_BUILD` when that variable lives in the shell. An already compiled dependency also keeps the NIF it first resolved, so `rm -rf _build/prod/lib/ex_ratatui` before switching ABI.

Output lands at `burrito_out/burrito_demo_linux` (~21 MB). For `macos`, `macos_silicon`, or `windows` artifacts, run the same command on a host matching the target OS — the bundled NIF is resolved from the build host's triple, so cross-host releases will fail to load. The [Burrito Demo CI workflow](../../.github/workflows/burrito_demo.yml) shows the per-target matrix.

## Run

```bash
./burrito_out/burrito_demo_linux
```

First run unpacks to `~/.local/share/.burrito/burrito_demo_erts-<erts version>_0.1.0/` and re-execs. Subsequent runs skip the unpack.

Controls match the original counter:

- `Up` / `k` — increment
- `Down` / `j` — decrement
- `q` — quit

A `--version` flag exits without entering raw mode — useful for CI smoke tests, and the `burrito_demo.yml` workflow uses it on every push. It loads the NIF before printing, so a NIF that cannot open on the target fails loudly instead of exiting 0.

## Clean

```bash
rm -rf _build deps burrito_out
rm -rf ~/.local/share/.burrito/burrito_demo_*
```

The cache directory is shared with other Burrito apps on the same machine, so the `burrito_demo_*` glob is important.

## How the wiring fits together

- `mix.exs` names `BurritoDemo.Application` as the OTP `:mod`, which supervises `BurritoDemo.CLI` as a `Task`.
- `BurritoDemo.CLI` is a thin shim: it reads `Burrito.Util.Args.argv/0` and hands off to `ExRatatui.Burrito.main/3`, so entry-point fixes arrive with ex_ratatui upgrades instead of freezing in this file. The delegate is a no-op outside a wrapped binary, so `mix test` and `iex -S mix` never boot the TUI over the session.
- The release `steps` run `&ExRatatui.Burrito.verify_linux_nif/1` between `:assemble` and `&Burrito.wrap/1`. On the linux target it scans the NIF this build loads and fails the release if it is a glibc build, rather than shipping a binary that dies at NIF load on every end-user machine.

`mix ex_ratatui.gen.burrito` generates this same wiring in a consumer project.

## What this proves

- ex_ratatui's precompiled NIF survives the Burrito unpack/relocate cycle on Linux x86_64, macOS (x86_64 and aarch64), and Windows x86_64.
- The OTP `:mod` callback plus a `Task` delegating to `ExRatatui.Burrito.main/3` is enough to bridge Burrito's entry point into a TUI render loop, with matching process exit codes for clean and crashed shutdowns.
- The linux target can be built on a glibc host — no musl container needed: `TARGET_ABI=musl` resolves the musl artifact from the rustler_precompiled cache, and the resulting binary loads it fine when run on that same glibc host.
