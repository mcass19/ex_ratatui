# Installation

Add `ex_ratatui` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_ratatui, "~> 0.19"}
  ]
end
```

Then run `mix deps.get`. The first compile downloads a precompiled NIF for the host, so no Rust toolchain is needed. The NIF loads lazily on first use, so compiling a project that depends on ExRatatui doesn't load it into the compiler VM.

Erlang and Gleam projects install differently; see [Erlang and Gleam](../runtimes/erlang_and_gleam.md).

## Requirements

- Elixir 1.17+
- Erlang/OTP 26 – 29

## Precompiled platforms

| OS | Architectures |
|---|---|
| Linux (glibc) | x86_64, aarch64, armv6 (hard float), riscv64 |
| Linux (musl) | x86_64, aarch64 |
| macOS | x86_64, aarch64 |
| Windows | x86_64 (MSVC and GNU) |

Each comes for NIF versions 2.16 (OTP 26), 2.17 (OTP 27 and 28), and 2.18 (OTP 29).

The Linux glibc binaries are built against old C libraries on purpose, and the release refuses to publish one that needs more: glibc 2.28 for aarch64, armv6, and riscv64 (so they load on Nerves systems and older distributions), and glibc 2.35 for x86_64.

The musl binaries depend on musl libc alone. Those published up to v0.11.2 linked `libgcc_s.so.1` dynamically, which stock musl systems (Alpine, Burrito payloads) don't ship; `apk add libgcc` fixes the resulting relocation error.

## Building from source

Install the [Rust toolchain](https://rustup.rs/) and set:

```sh
export EX_RATATUI_BUILD=true
```

Or, without an env var, in `config/config.exs`:

```elixir
config :rustler_precompiled, :force_build, ex_ratatui: true
```

The application config takes precedence over `EX_RATATUI_BUILD`, and `config :rustler_precompiled, force_build_all: true` takes precedence over both.

Either way, the consuming project needs Rustler in its own dependencies. ExRatatui declares `:rustler` as optional, and optional dependencies aren't fetched transitively, so without it the build fails with `Rustler.Compiler is not available`:

```elixir
{:rustler, ">= 0.0.0"}
```

## Depending on a git tag

A git dependency (`{:ex_ratatui, github: "mcass19/ex_ratatui", tag: "..."}`) has to build from source. The checksum file for a release's precompiled NIFs is committed only after the tag triggers their build, so each tag predates its own checksums and the precompiled path fails with `the precompiled NIF file does not exist in the checksum file`. The Hex package always carries the complete checksum file.
