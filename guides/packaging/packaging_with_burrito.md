# Packaging with Burrito

Shipping a TUI built on `ExRatatui.App` normally means asking end users to install Erlang, Elixir, and (often) a Rust toolchain before they can run a single command. [Burrito](https://github.com/burrito-elixir/burrito) flips that around: it wraps an OTP release into one statically-linked native binary per OS/arch, distributed as a single file. The end user downloads it, runs it, and the BEAM plus the ex_ratatui NIF unpack into a per-user cache directory on first launch.

ex_ratatui itself stays a library — it does not depend on Burrito at runtime and does not produce its own binaries. Burrito is something a consumer project opts into.

## Prerequisites

- Erlang/OTP and Elixir matching ex_ratatui's `mix.exs` requirements.
- `zig` **exactly 0.15.2**. Burrito 1.5 hard-pins this; any other version is rejected at `mix release` time. `mise install zig@0.15.2` is the shortest path; the broader install matrix is on the [Burrito README](https://github.com/burrito-elixir/burrito#requirements).
- `xz` on `PATH`. Usually already present on Linux and macOS.

A `.mise.toml` in the consumer project keeps the toolchain reproducible:

```toml
[tools]
zig = "0.15.2"
```

## Quick start

`mix ex_ratatui.gen.burrito` does the whole setup in one command:

```sh
mix ex_ratatui.gen.burrito --tui-module MyTui.TUI --ci github
```

It patches `mix.exs`, scaffolds the Application and CLI modules, and optionally drops the matrix CI workflow into `.github/workflows/`. The generator is opt-in: ex_ratatui declares `igniter` as `optional: true`, so projects that never run the task pay nothing for it.

That leaves nothing to do but [build](#building). The section below is the same wiring by hand — worth reading to understand what the generator wrote, or to retrofit a project that already has its own Application and release config.

## Wiring it by hand

[`examples/burrito_demo/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/burrito_demo) in this repo is the finished version of everything below, and what the generator produces matches it.

Start from a normal OTP-shaped TUI project:

```sh
mix new my_tui --sup
cd my_tui
```

Add ex_ratatui and burrito to `mix.exs`:

```elixir
defp deps do
  [
    {:ex_ratatui, "~> 0.12"},
    {:burrito, "~> 1.5"}
  ]
end
```

Add a `releases/0` and reference it from `project/0`:

```elixir
def project do
  [
    app: :my_tui,
    version: "0.1.0",
    elixir: "~> 1.17",
    deps: deps(),
    releases: releases()
  ]
end

defp releases do
  [
    my_tui: [
      steps: [:assemble, &ExRatatui.Burrito.verify_linux_nif/1, &Burrito.wrap/1],
      burrito: [
        targets: [
          linux: [os: :linux, cpu: :x86_64],
          macos: [os: :darwin, cpu: :x86_64],
          macos_silicon: [os: :darwin, cpu: :aarch64],
          windows: [os: :windows, cpu: :x86_64]
        ]
      ]
    ]
  ]
end
```

`ExRatatui.Burrito.verify_linux_nif/2` is a guard against the most common packaging mistake: building the linux target without `TARGET_ABI=musl` (covered under [Building](#building)) assembles a glibc NIF that cannot load inside burrito's musl wrapper — the step fails the build with the exact fix instead of letting a broken binary ship. It is wired as the arity-1 capture above; the second argument names the NIF to scan and defaults to the one this build loads.

Wire the Application as Burrito's entry point. Burrito expects a `:mod` in `application/0`; the CLI module below is a supervised `Task` that reads command-line arguments via `Burrito.Util.Args.argv/0`:

```elixir
def application do
  [
    extra_applications: [:logger],
    mod: {MyTui.Application, []}
  ]
end
```

```elixir
# lib/my_tui/application.ex
defmodule MyTui.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyTui.CLI
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyTui.Supervisor)
  end
end
```

```elixir
# lib/my_tui/cli.ex
defmodule MyTui.CLI do
  use Task

  @version Mix.Project.config()[:version]

  def start_link(_arg) do
    Task.start_link(__MODULE__, :main, [Burrito.Util.Args.argv()])
  end

  def main(argv) do
    ExRatatui.Burrito.main(MyTui.TUI, argv, name: "my_tui", version: @version)
  end
end
```

`MyTui.TUI` is any module using `ExRatatui.App`. The entry-point protocol itself — boot the TUI, wait for it to exit, stop the VM with a matching exit code so the wrapper returns control to the shell — lives in `ExRatatui.Burrito.main/3`, so its fixes arrive with ex_ratatui upgrades instead of freezing in this module. Three behaviours it provides matter beyond the happy path. It is a no-op outside a burrito-wrapped binary: the supervised task starts on *every* application boot — `mix test` and `iex -S mix` included — and burrito's `__BURRITO` env var is the supported way to run the TUI only inside the wrapped binary. `--version` anywhere in argv prints and exits 0 without a TTY, first forcing the NIF `dlopen` so a NIF/host mismatch fails loudly. And every failure path — the TUI crashing, failing to start, or the entry point raising — reports on stderr and exits 1 instead of hanging the wrapper on an idle BEAM. The `use Task` shape matters too: keying the child spec on the CLI module keeps the wiring idempotent and cannot collide with unrelated `Task` children in the tree.

## Building

Build a single target at a time — Burrito tries to build every declared target by default, which fails on the first host that's missing a tool needed for *some other* target:

```sh
TARGET_ABI=musl BURRITO_TARGET=linux MIX_ENV=prod mix release --overwrite
```

`TARGET_ABI=musl` is required for the `linux` target. Burrito's linux wrapper uses a musl runtime, so the bundled NIF must be the musl variant — without the override, `rustler_precompiled` resolves the NIF from the build host (typically glibc), and a glibc `.so` cannot load inside the musl environment, so the wrapped binary crashes at NIF load. The musl artifacts are fully self-contained since ex_ratatui 0.12.0 (older ones additionally needed `libgcc_s.so.1` on the target — see #83). The other targets do not need this override; pass `TARGET_ABI=musl` only when `BURRITO_TARGET=linux`.

`TARGET_ABI` only chooses between precompiled artifacts, so it is silently ignored whenever the crate is built from source — with `EX_RATATUI_BUILD` exported, or `:force_build` set in the `rustler_precompiled` config, the release gets a NIF compiled against the build host's glibc no matter what `TARGET_ABI` says. Unset both before releasing the linux target.

Output lands in `burrito_out/`:

```
burrito_out/
└── my_tui_linux       # 15–20 MB, statically linked, ready to ship
```

Repeat with `BURRITO_TARGET=macos`, `macos_silicon`, `windows` to produce the other artifacts — **on a host that matches the target OS**. While zig can cross-compile burrito's wrapper from any host, `rustler_precompiled` resolves the bundled NIF from the build host's triple, so a macOS or Windows release built on Linux ends up with a Linux `.so` inside and fails to load. The per-target CI matrix below is the canonical way to produce all artifacts in one pipeline.

## Testing the wrapped binary

The same checklist works on every target — it is what this repo's CI runs against the demo, plus the interactive checks CI cannot do.

Non-interactive smoke — proves the BEAM boots and the NIF loads without a TTY:

```sh
./burrito_out/my_tui_linux --version
echo $?        # 0, after printing "my_tui 0.1.0"
```

On Windows (PowerShell), the same pair is `.\burrito_out\my_tui_windows.exe --version` and `$LASTEXITCODE`.

Interactive — run the binary on a real terminal: the TUI takes over the alternate screen, input works, and quitting restores the shell. Then check the exit codes: `echo $?` reports 0 after a clean quit, and 1 when the TUI crashed or the binary ran without a usable terminal (piped stdin, for example — it must exit, not hang).

Dev-session gate — from the consumer project itself, `mix test` and `iex -S mix` must behave normally: the CLI task starts with the application but never boots the TUI outside the wrapped binary.

One caveat when iterating: the wrapper caches the extracted release by version, so a rebuild with an unchanged `version:` re-executes the *cached* copy. Clear it between test builds with the wrapper's built-in maintenance command:

```sh
./burrito_out/my_tui_linux maintenance uninstall
```

## Per-target CI matrix

A clean CI shape gives each runner one target on its native OS, so no host needs the union of all tools. The [`burrito_demo.yml`](https://github.com/mcass19/ex_ratatui/blob/main/.github/workflows/burrito_demo.yml) workflow in this repo is the reference layout — copy it into a consumer project and adapt the artifact upload destination from a 7-day artifact to a GitHub Release:

```yaml
strategy:
  matrix:
    include:
      - { os: ubuntu-latest,  target: linux,         artifact: my_tui_linux }
      - { os: macos-15-intel,       target: macos,         artifact: my_tui_macos }
      - { os: macos-14,       target: macos_silicon, artifact: my_tui_macos_silicon }
      - { os: windows-latest, target: windows,       artifact: my_tui_windows.exe }
```

Each job runs:

```yaml
env:
  BURRITO_TARGET: ${{ matrix.target }}
  MIX_ENV: prod
run: mix release --overwrite
```

For tagged releases, swap the `actions/upload-artifact` step for `softprops/action-gh-release` and the binaries land directly on the GitHub Release page — the end-user install pattern becomes:

```sh
curl -L https://github.com/<owner>/<repo>/releases/latest/download/my_tui_linux \
  -o my_tui && chmod +x my_tui && ./my_tui
```

## The shape of a wrapped app

Everything above treats the binary as a black box. Opening it up explains most of the gotchas that follow — a wrapped app is a single file at rest and an ordinary OTP release once it runs, and the first launch turns one into the other:

```
   my_tui_linux (~21 MB)             ~/.local/share/.burrito/
  ┌───────────────────────┐         ┌───────────────────────────────────────┐
  │ zig launcher          │ unpack  │ my_tui_erts-17.0.4_1.0.0/             │
  │ ───────────────────── │ ──────► │  ├─ bin/                release entry │
  │ compressed payload    │  (once) │  ├─ erts-17.0.4/        the BEAM      │
  │  = the whole release  │         │  ├─ lib/…/priv/native/  the NIFs      │
  └───────────────────────┘         │  ├─ releases/1.0.0/                   │
              │                     │  └─ _metadata.json                    │
              └──────── re-exec ───►└───────────────────────────────────────┘
```

The binary itself is a zig-compiled launcher wrapped around a compressed copy of the release. Every launch it derives the cache directory name, unpacks the payload there if the directory is missing, then execs that release's standard `bin/<app> start`. So the first run pays for the unpack and every later run goes straight to the re-exec.

That directory name is `<app>_erts-<erts version>_<app version>`, and both halves matter:

- **`erts-17.0.4`** is the version of the ERTS bundled at build time — the runtime the release was compiled against, *not* the OTP release number. ERTS 17.0.x ships with OTP 29, ERTS 16.x with OTP 28.
- **`1.0.0`** is the app version from `mix.exs`.

Because the name pins both, a rebuilt binary never reuses a stale unpack: bumping the app version, or rebuilding on a newer OTP, unpacks into a fresh directory and leaves the old one alone. That is also why the cache accumulates directories over time — [NIF cache location](#nif-cache-location) below has the per-OS paths for finding and clearing them.

The wrapped BEAM has full TTY, SIGWINCH, and Ctrl-C handling — nothing in the wrapper interferes with the terminal once the BEAM takes over.

## Gotchas

### Terminal handoff

Burrito's wrapper writes a few diagnostic lines to stderr during the first-run unpack, then `exec`s into the cached release. After the exec, nothing in the wrapper is between the BEAM and the TTY — raw mode, alt screen entry, `SIGWINCH` resize events, and `Ctrl-C` all behave exactly like a `mix run`'d TUI. The first-run delay is the only thing the wrapper adds; subsequent runs skip the unpack entirely.

### macOS Gatekeeper

An unsigned binary downloaded over the network gets the `com.apple.quarantine` extended attribute. Gatekeeper refuses to run it until the attribute is cleared:

```sh
xattr -d com.apple.quarantine my_tui_macos
./my_tui_macos
```

Proper signing + notarization removes the friction for end users, but it is consumer-side concern — neither ex_ratatui nor Burrito ship signing keys. The [Apple developer docs on notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) cover the workflow.

### Windows SmartScreen / antivirus

Unsigned binaries on Windows frequently trigger SmartScreen prompts and get flagged by aggressive AV products. Authenticode signing eliminates the SmartScreen warning. Until that's in place, the README of a release should mention "if Windows blocks the binary, click More info → Run anyway."

### NIF cache location

The unpacked release lives in a per-user cache, one directory per `<app>_erts-<erts version>_<app version>` combination:

| OS | Path |
|---|---|
| Linux | `~/.local/share/.burrito/` |
| macOS | `~/Library/Application Support/.burrito/` |
| Windows | `%LOCALAPPDATA%\.burrito\` |

Inside one of those directories, the ex_ratatui NIF sits at `lib/ex_ratatui-<v>/priv/native/libex_ratatui-*.so` (or `.dylib` / `.dll`) — handy to know when debugging "the NIF won't load." Clearing a cache is safe at any time; the next launch just pays for the unpack again.

### Per-target dependencies in the payload

OTP releases bundle the contents of every dependency's `priv/` directory. If `priv/native/` in the consumer's `_build/<env>/lib/ex_ratatui/` happens to hold multiple precompiled NIF variants (a side effect of bumping ex_ratatui versions across dev sessions), all of them ship inside the binary even though only one is used. Setting the [`TARGET_*` environment variables](https://hexdocs.pm/rustler_precompiled/RustlerPrecompiled.html#module-environment-variables) before `mix deps.compile` (or wiping `_build/<env>/lib/ex_ratatui/priv/native/` between rebuilds) keeps the payload to a single matching variant.

This is payload weight, not a correctness problem, and `verify_linux_nif/2` scans only the variant the release actually loads — a leftover glibc `.so` sitting next to the musl one will not fail the build.

## Where to next

- The complete reference project: [`examples/burrito_demo/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/burrito_demo).
- The regression CI building and smoke-testing the linux (musl), macOS apple-silicon, and windows targets on every push: [`.github/workflows/burrito_demo.yml`](https://github.com/mcass19/ex_ratatui/blob/main/.github/workflows/burrito_demo.yml).
- Burrito's own docs for advanced topics (custom plugins, ERTS resolvers, signing hooks): [hexdocs.pm/burrito](https://hexdocs.pm/burrito).
