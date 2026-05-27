# Transports

ExRatatui apps run against one of five transports. The model code (mount, render, handle_event, handle_info) is identical across all of them — only the surrounding plumbing differs. This guide is the canonical reference for *what works where*; each row of the matrix below links to a dedicated guide that goes deeper.

## The five transports

| Transport | Entry point | Where the terminal lives | Where the app callbacks live |
|---|---|---|---|
| **Local** | `ExRatatui.run/2` or `ExRatatui.Server.start_link(transport: :local)` | Host tty | Same node, same process |
| **Byte-stream Session** | `ExRatatui.Server.start_link(transport: :session, ...)` | Caller-owned bytes (any transport speaking ANSI in + bytes out) | Same node |
| **SSH** | `ExRatatui.SSH.Daemon.start_link/1` | Remote SSH client's tty | App-side; one Server per channel |
| **Distributed** | `ExRatatui.Distributed.attach/2` on the client; `ExRatatui.Distributed.Listener` on the app node | Local node's tty | Remote node, behind Erlang distribution |
| **CellSession** | `ExRatatui.Server.start_link(transport: :cell_session, ...)` | None — a `%CellSession{}` exposes the cell buffer instead of bytes (LiveView, headless tests, framebuffers) | Same node |

The internal telemetry tags match: `transport: :local`, `:session`, `:distributed_server`, `:cell_session`. SSH wraps `:session`.

## Feature matrix

`✓` = supported, `—` = not applicable for this transport, `✗` = not supported today (issue / follow-up exists).

| Feature | Local | Session | SSH | Distributed | CellSession |
|---|:-:|:-:|:-:|:-:|:-:|
| Every widget renders (Paragraph, List, Table, Block, Gauge, Chart, …) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Key events (`Event.Key`) | ✓ | ✓ | ✓ | ✓ | ✓ (`feed_input/2`) |
| Mouse events (`Event.Mouse`) | ✓ | ✓ | ✓ | ✓ | ✓ (`feed_input/2`) |
| Resize events (`Event.Resize`) | ✓ | ✓ | ✓ | ✓ | ✓ (`resize/3`) |
| Bracketed paste (`Event.Paste`) | ✓ | ✗ (VTE parser doesn't decode `CSI 200~/201~` yet) | ✗ (same) | ✗ (same) | — (caller constructs `%Event.Paste{}` directly) |
| Focus events (`Event.FocusGained` / `FocusLost`) | ✓ opt-in via `run(fn, focus_events: true)` | ✗ | ✗ | ✗ | — |
| Image rendering: `:halfblocks` | ✓ | ✓ | ✓ | ✓ | ✓ (forced on this transport) |
| Image rendering: `:kitty` / `:sixel` / `:iterm` | ✓ (auto-probe via `auto_local_protocol/1`) | ✓ (per-image at construction) | ✓ (`image_protocol:` opt on the daemon) | ✓ (`image_protocol:` opt on `attach/2`) | ✗ (escape sequences can't survive cell diffing) |
| Image protocol auto-detection | ✓ (`probe_image_protocol: true` on mount) | ✗ (caller decides) | ✗ (caller decides) | ✗ (caller decides) | — |
| OSC 52 clipboard copy (write to terminal's clipboard via emitted bytes) | ✓ (write to stdout) | ✓ (write to the transport's byte writer) | ✓ (same — bytes cross the SSH channel) | ✓ (same — bytes ride the distribution renderer stream) | ✗ (no byte channel; route as an intent if the consumer can act on it) |
| Intents (forward opaque terms to the transport) | — | — | — | — | ✓ (`{:cell_session, cs, cell_writer, intent_writer}` 4-tuple) |
| `:render?` runtime opt (skip render after handler returns) | ✓ | ✓ | ✓ | ✓ | ✓ |
| `:commands` runtime opt (long-running work via `ExRatatui.Command`) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Telemetry: `[:ex_ratatui, :transport, :connect/:disconnect]` | ✓ | ✓ | ✓ | ✓ | ✓ |
| Telemetry: `[:ex_ratatui, :render, :frame]` | ✓ | ✓ | ✓ | ✓ | ✓ |

### Notes on the gaps

- **Bracketed paste over byte-stream transports** (Session, SSH, Distributed): the input parser is a custom VTE state machine, not crossterm. It doesn't decode `CSI 200~/201~` markers today. Apps that need pasted-blob handling on those transports can construct `%ExRatatui.Event.Paste{content: text}` themselves and feed it through whatever input pipeline they own — the widget-side contract (`text_input_insert_str/2`, `textarea_insert_str/2`) is transport-agnostic.
- **Focus events over byte-stream transports**: same VTE-parser gap, plus the protocol question of whether SSH-side terminal-focus events are even useful for the app-side process. Off the roadmap unless someone asks.
- **Images over CellSession**: the resolved protocol is always `:halfblocks`. Kitty / Sixel / iTerm2 encoders emit escape sequences, which a cell buffer can't represent. LiveView (and any other CellSession consumer) gets cell-painted halfblock approximations of the source image instead — works in every browser but the resolution is per-character-pair, not per-pixel.
- **OSC 52 on CellSession**: same root cause as images — no byte channel. The intent mechanism is the escape hatch: emit `{:clipboard_copy, content}` from a handler, register an `intent_writer_fn` on the transport tuple, and have that writer call `navigator.clipboard.writeText` (or equivalent).

## Where to go from here

- [Local terminal: getting started](getting_started.md)
- [SSH transport](ssh_transport.md)
- [Distributed transport](distributed_transport.md)
- [Cell sessions (LiveView, headless)](cell_session.md)
- [Custom transports](custom_transports.md) — implement a fifth one
- [Paste and clipboard](paste_and_clipboard.md) — bracketed paste details + the OSC 52 snippet
- [Images](images.md) — the protocol matrix in depth
