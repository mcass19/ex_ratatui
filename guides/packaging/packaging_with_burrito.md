# Packaging with Burrito

Shipping a TUI built on `ExRatatui.App` normally means asking end users to
install Erlang, Elixir, and (often) a Rust toolchain before they can run a
single command. [Burrito](https://github.com/burrito-elixir/burrito) flips
that around: it wraps an OTP release into one statically-linked native
binary per OS/arch, distributed as a single file. The end user downloads
it, runs it, and the BEAM plus the ex_ratatui NIF unpack into a per-user
cache directory on first launch.

ex_ratatui itself stays a library — it does not depend on Burrito at
runtime and does not produce its own binaries. Burrito is something a
consumer project opts into.

## The shape of a wrapped app

```
                                  one-time on first run
                          ┌────────────────────────────────┐
                          ▼                                │
  ┌──────────────────┐    ┌─────────────────────────────┐  │
  │  my_tui_linux    │ ─► │  ~/.local/share/.burrito/   │  │
  │  (~17 MB ELF)    │    │   my_tui_erts-28_1.0.0/     │  │
  └──────────────────┘    │    ├─ erts-28/              │  │
           │              │    ├─ lib/ex_ratatui-0.9.0/ │  │
           │              │    │   priv/native/*.so     │  │
           │              │    ├─ releases/1.0.0/       │  │
           │              │    └─ bin/                  │  │
           │              └─────────────────────────────┘  │
           │                                               │
           └─── re-exec into the cached release ───────────┘
```

Build time, the burrito wrapper is a zig-compiled launcher embedding a
compressed payload (the full OTP release). At runtime, the wrapper checks
whether the cache already holds an extracted copy of this exact version,
extracts the payload if not, and execs the standard
`release/bin/<app> start` entry point. The wrapped BEAM has full TTY,
SIGWINCH, and Ctrl-C handling — nothing in the wrapper interferes with the
terminal once the BEAM takes over.

## Prerequisites

- Erlang/OTP and Elixir matching ex_ratatui's `mix.exs` requirements.
- `zig` **exactly 0.15.2**. Burrito 1.5 hard-pins this; any other version
  is rejected at `mix release` time. `mise install zig@0.15.2` is the
  shortest path; the broader install matrix is on the
  [Burrito README](https://github.com/burrito-elixir/burrito#requirements).
- `xz` on `PATH`. Usually already present on Linux and macOS.

A `.mise.toml` in the consumer project keeps the toolchain reproducible:

```toml
[tools]
zig = "0.15.2"
```

## Quick start

The fastest path is reading
[`examples/burrito_demo/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/burrito_demo)
in this repo — it's a complete working project. The walkthrough below
mirrors that example and is the same shape `mix ex_ratatui.gen.burrito`
produces.

Start from a normal OTP-shaped TUI project:

```sh
mix new my_tui --sup
cd my_tui
```

Add ex_ratatui and burrito to `mix.exs`:

```elixir
defp deps do
  [
    {:ex_ratatui, "~> 0.9"},
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
      steps: [:assemble, &Burrito.wrap/1],
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

Wire the Application as Burrito's entry point. Burrito expects a `:mod`
in `application/0` and reads command-line arguments via
`Burrito.Util.Args.argv/0`:

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
      {Task, fn -> MyTui.CLI.main(Burrito.Util.Args.argv()) end}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyTui.Supervisor)
  end
end
```

```elixir
# lib/my_tui/cli.ex
defmodule MyTui.CLI do
  def main(_argv) do
    {:ok, pid} = MyTui.TUI.start_link([])
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end

    System.stop(0)
  end
end
```

`MyTui.TUI` is any module using `ExRatatui.App`. The CLI's job is to boot
that GenServer, wait for it to exit, then stop the VM so the wrapper
returns control to the shell.

## Building

Build a single target at a time — Burrito tries to build every declared
target by default, which fails on the first host that's missing a tool
needed for *some other* target:

```sh
BURRITO_TARGET=linux MIX_ENV=prod mix release --overwrite
```

Output lands in `burrito_out/`:

```
burrito_out/
└── my_tui_linux       # 15–20 MB, statically linked, ready to ship
```

Repeat with `BURRITO_TARGET=macos`, `macos_silicon`, `windows` to produce
the other artifacts — **on a host that matches the target OS**. While
zig can cross-compile burrito's wrapper from any host,
`rustler_precompiled` resolves the bundled NIF from the build host's
triple, so a macOS or Windows release built on Linux ends up with a
Linux `.so` inside and fails to load. The per-target CI matrix below is
the canonical way to produce all artifacts in one pipeline.

## Per-target CI matrix

A clean CI shape gives each runner one target on its native OS, so no host
needs the union of all tools. The
[`burrito_demo.yml`](https://github.com/mcass19/ex_ratatui/blob/main/.github/workflows/burrito_demo.yml)
workflow in this repo is the reference layout — copy it into a consumer
project and adapt the artifact upload destination from a 7-day artifact to
a GitHub Release:

```yaml
strategy:
  matrix:
    include:
      - { os: ubuntu-latest,  target: linux,         artifact: my_tui_linux }
      - { os: macos-13,       target: macos,         artifact: my_tui_macos }
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

For tagged releases, swap the `actions/upload-artifact` step for
`softprops/action-gh-release` and the binaries land directly on the GitHub
Release page — the end-user install pattern becomes:

```sh
curl -L https://github.com/<owner>/<repo>/releases/latest/download/my_tui_linux \
  -o my_tui && chmod +x my_tui && ./my_tui
```

## Gotchas

### Terminal handoff

Burrito's wrapper writes a few diagnostic lines to stderr during the
first-run unpack, then `exec`s into the cached release. After the exec,
nothing in the wrapper is between the BEAM and the TTY — raw mode, alt
screen entry, `SIGWINCH` resize events, and `Ctrl-C` all behave exactly
like a `mix run`'d TUI. The first-run delay is the only thing the wrapper
adds; subsequent runs skip the unpack entirely.

### macOS Gatekeeper

An unsigned binary downloaded over the network gets the
`com.apple.quarantine` extended attribute. Gatekeeper refuses to run it
until the attribute is cleared:

```sh
xattr -d com.apple.quarantine my_tui_macos
./my_tui_macos
```

Proper signing + notarization removes the friction for end users, but it
is consumer-side concern — neither ex_ratatui nor Burrito ship signing
keys. The
[Apple developer docs on notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
cover the workflow.

### Windows SmartScreen / antivirus

Unsigned binaries on Windows frequently trigger SmartScreen prompts and
get flagged by aggressive AV products. Authenticode signing eliminates
the SmartScreen warning. Until that's in place, the README of a release
should mention "if Windows blocks the binary, click More info → Run
anyway."

### NIF cache location

The unpacked release lives in a per-user cache:

| OS | Path |
|---|---|
| Linux | `~/.local/share/.burrito/<app>_erts-<v>_<version>/` |
| macOS | `~/Library/Application Support/.burrito/<app>_erts-<v>_<version>/` |
| Windows | `%LOCALAPPDATA%\.burrito\<app>_erts-<v>_<version>\` |

The directory name encodes the ERTS and release version, so multiple
versions of the same app can coexist. The ex_ratatui NIF lives at
`lib/ex_ratatui-<v>/priv/native/libex_ratatui-*.so` (or `.dylib` /
`.dll`) inside that directory — handy to know when debugging "the NIF
won't load."

### Per-target dependencies in the payload

OTP releases bundle the contents of every dependency's `priv/` directory.
If `priv/native/` in the consumer's `_build/<env>/lib/ex_ratatui/` happens
to hold multiple precompiled NIF variants (a side effect of bumping
ex_ratatui versions across dev sessions), all of them ship inside the
binary even though only one is used. Setting the
[`TARGET_*` environment variables](https://hexdocs.pm/rustler_precompiled/RustlerPrecompiled.html#module-environment-variables)
before `mix deps.compile` (or wiping `_build/<env>/lib/ex_ratatui/priv/native/`
between rebuilds) keeps the payload to a single matching variant.

## Generator shortcut

Once `mix ex_ratatui.gen.burrito` lands, the entire setup above collapses
into:

```sh
mix ex_ratatui.gen.burrito --app my_tui --ci github
```

The task patches `mix.exs`, scaffolds the Application + CLI modules, and
optionally drops the matrix CI workflow into `.github/workflows/`. The
generator is opt-in: ex_ratatui declares `igniter` as `optional: true`,
so projects that never run the task pay nothing for it.

## Where to next

- The complete reference project: [`examples/burrito_demo/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/burrito_demo).
- The regression CI showing all four targets building and smoke-testing:
  [`.github/workflows/burrito_demo.yml`](https://github.com/mcass19/ex_ratatui/blob/main/.github/workflows/burrito_demo.yml).
- Burrito's own docs for advanced topics (custom plugins, ERTS resolvers,
  signing hooks): [hexdocs.pm/burrito](https://hexdocs.pm/burrito).
