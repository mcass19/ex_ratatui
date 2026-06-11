# Architecture

How ExRatatui bridges Elixir and Rust, and how the runtime processes are laid out per transport. Nothing here is required reading for building apps — it exists for debugging, for writing custom transports, and for the curious.

## The NIF bridge

ExRatatui connects Elixir to the Rust [ratatui](https://ratatui.rs) library through [Rustler](https://github.com/rustler-beam/rustler) NIFs (Native Implemented Functions):

```
Elixir structs -> encode to maps -> Rust NIF -> decode to ratatui types -> render to terminal
Terminal events -> Rust NIF (DirtyIo) -> encode to tuples -> Elixir Event structs
```

- **Rendering:** Elixir widget structs are encoded as string-keyed maps, passed across the NIF boundary, and decoded into ratatui widget types for rendering.
- **Events:** The `poll_event` NIF runs on BEAM's DirtyIo scheduler, so event polling never blocks normal Elixir processes.
- **Terminal state:** Each process holds its own terminal reference via Rust `ResourceArc`, supporting two backends — a real crossterm terminal and a headless test backend for CI (see [Testing](testing.md)). The terminal is automatically restored when the reference is garbage collected.
- **Layout:** Ratatui's constraint-based layout engine is exposed directly, computing split rectangles on the Rust side and returning them as `%Rect{}` structs.

Precompiled binaries are provided via [rustler_precompiled](https://github.com/philss/rustler_precompiled), so depending on `ex_ratatui` does not require the Rust toolchain. The native library is loaded lazily on first use — compiling a project that depends on `ex_ratatui` does not load the NIF into the compiler VM.

## Process architecture

Each transport builds on the same internal `Server`, a GenServer that owns the render loop and dispatches to the `ExRatatui.App` callbacks:

```
Local transport:
  Supervisor
  └── Server (GenServer)
        ├── owns terminal reference (NIF)
        ├── polls events on DirtyIo scheduler
        └── calls the app's mount/render/handle_event

SSH transport:
  Supervisor
  └── SSH.Daemon (GenServer, wraps :ssh.daemon)
        └── per client:
              SSH channel (:ssh_server_channel)
              ├── owns Session (in-memory terminal)
              ├── feeds client bytes through Session's ANSI parser
              └── Server (GenServer)
                    └── calls the app's mount/render/handle_event

Distributed transport:
  App node                              Client node
  ├── Distributed.Listener              └── Distributed.Client (GenServer)
  │   └── DynamicSupervisor                   ├── owns terminal reference (NIF)
  │       └── per client:                     ├── polls events locally
  │             Server (GenServer)            └── sends events → Server
  │             └── sends widgets → Client          receives widgets ← Server
  └── No NIF needed here
```

All transports provide full session isolation — each connected client gets its own `Server` process with independent state. The [Transports](../transports/transports.md) guide has the cross-transport feature matrix; [Custom Transports](../transports/custom_transports.md) documents the contract for plugging in new ones.

## Related

- [Debugging](debugging.md) — `Runtime.snapshot/1`, tracing, and common errors, including NIF rebuilds.
- [Performance](performance.md) — what the render loop costs and how to tune it.
- [Testing](testing.md) — the headless backend in practice.
