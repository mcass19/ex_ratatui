# Images

Render real images — PNG, JPEG, GIF, WebP, BMP — inside a TUI. The same model code displays Kitty graphics in a Kitty terminal, halfblocks in Livebook, and adapts gracefully when you don't know what the audience's terminal supports.

Built on [ratatui-image](https://github.com/ratatui/ratatui-image).

## Quick start

```elixir
{:ok, picture} = ExRatatui.Image.new(File.read!("priv/slides/cover.png"))

def view(_model, frame) do
  area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
  [{picture, area}]
end
```

`ExRatatui.Image.new/2` decodes once and returns a stateful widget handle. Hold it in your model and reuse it across renders — re-encoding only happens when the protocol changes or the rect resizes. Image format is auto-detected from the bytes; no extension or content-type hint required.

Bad bytes return `{:error, {:decode_failed, message}}` rather than raising, so you can render a placeholder gracefully.

## Options

`ExRatatui.Image.new/2` accepts a keyword list:

| Option | Values | Default | What it does |
|---|---|---|---|
| `:protocol` | `:auto`, `:halfblocks`, `:kitty`, `:sixel`, `:iterm2` | `:auto` | Which terminal protocol to render with. `:auto` resolves at render time against the transport (see [resolution table](#protocol-resolution)). Explicit protocols are honored except over `CellSession` where `:halfblocks` is forced. |
| `:resize` | `:fit`, `:crop`, `:scale` | `:fit` | `:fit` preserves aspect inside the rect (anchored top-left if smaller). `:crop` preserves aspect, fills the rect, crops the overflow. `:scale` stretches to fill (no aspect preservation). |
| `:background` | `nil` or `{r, g, b}` (each `0..255`) | `nil` | Color used to fill transparent pixels / unused area for halfblocks. |

To change options later, build a new handle — the widget struct just wraps the resource ref.

## Protocol resolution

Each transport stamps its own capability hint. Widget-level `:auto` resolves against it:

| Transport | Capability | `:auto` resolves to | Explicit `:kitty` etc. |
|---|---|---|---|
| Local terminal (no probe) | `RawTerminal { hint: nil }` | `:halfblocks` | Honored — emits raw escapes |
| Local terminal (after probe) | `Local { picker_protocol, font_size }` | The detected protocol | Honored |
| SSH (no opt) | `RawTerminal { hint: nil }` | `:halfblocks` | Honored |
| SSH (`image_protocol: :kitty`) | `RawTerminal { hint: :kitty }` | `:kitty` | Honored |
| Distributed (no opt) | `RawTerminal { hint: nil }` | `:halfblocks` | Honored |
| Distributed (`image_protocol: :kitty`) | `RawTerminal { hint: :kitty }` | `:kitty` | Honored |
| `CellSession` (Livebook / Kino) | `CellOnly` | `:halfblocks` | **Forced to `:halfblocks`** (escape sequences can't survive cell diffing) |

This means **the same model code is portable**: a slide deck that renders pixel-perfect Kitty graphics in your local Kitty terminal will silently fall back to halfblocks when the same `ExRatatui.App` is driven from a Livebook cell — no branching.

### Probing the local terminal

`ExRatatui.Image.auto_local_protocol/1` writes a query escape sequence and waits for the terminal's reply (this is ratatui-image's `Picker::from_query_stdio`). On success the result is cached on the terminal reference; on no-TTY / no-reply the cache stays empty and `:auto` falls back to halfblocks. Either way it's safe to call from any environment.

There are two ways to wire it in.

**Inside `ExRatatui.App`:** return `probe_image_protocol: true` from `mount/1`. The runtime calls `auto_local_protocol/1` for you right after mount, on the `:local` transport only (CellSession forces halfblocks; SSH / Distributed use the session-level `:image_protocol` opt instead):

```elixir
@impl true
def mount(_opts) do
  {:ok, initial_state, probe_image_protocol: true}
end
```

The probe is automatically skipped under `test_mode: {w, h}` so headless tests don't accidentally write probe escapes.

**Outside `ExRatatui.App`** (e.g. `ExRatatui.run/1`):

```elixir
ExRatatui.run(fn terminal ->
  ExRatatui.Image.auto_local_protocol(terminal)
  # ... rest of your app
end)
```

If you want to make your own decision based on the probe, `ExRatatui.Image.probe_terminal/0` returns `{:ok, %{protocol: atom, font_size: {w, h}}}` or `{:error, reason}` without touching any cache.

### Telling SSH / Distributed what protocol the client supports

You can't probe an SSH or Distributed client terminal, so the audience declares it at start time:

```elixir
# SSH daemon
ExRatatui.SSH.Daemon.start_link(
  mod: MyApp.TUI,
  port: 2222,
  image_protocol: :kitty
)

# Distributed attach
ExRatatui.Distributed.attach(:"app@host", MyApp.TUI, image_protocol: :kitty)
```

Per-image explicit choices (`ExRatatui.Image.new(bytes, protocol: :sixel)`) are always honored, regardless of the session-level hint.

## Font-size caveat

Cells aren't pixels. The render pipeline needs the terminal's cell-pixel dimensions to scale Kitty / Sixel / iTerm2 payloads correctly. The default is `(8, 16)`; `auto_local_protocol/1` replaces it with the real value reported by the terminal. If your Kitty graphics look mis-scaled, run the probe.

## Examples

* [`examples/headless_image.exs`](../examples/headless_image.exs) — fetch a photo, render through `CellSession`, dump cells to stdout. The Livebook / Kino path.
* [`examples/image_demo.exs`](../examples/image_demo.exs) — interactive viewer with `p` to cycle protocol and `r` to cycle resize mode.
* [`examples/slides.exs`](../examples/slides.exs) — three-slide deck with arrow-key navigation: title, image, code. The "TUI slides with photos" use case.

All three accept an `IMAGE_PATH` env var, default to fetching from `picsum.photos` once at startup, and fall back to an embedded 1×1 PNG if the network is unreachable.

## Telemetry

Each `ExRatatui.Image.new/2` call emits a `[:ex_ratatui, :image, :decode]` span:

* `:start` — `%{format: atom, bytes: non_neg_integer}` (format sniffed from magic bytes: `:png`, `:jpeg`, `:gif`, `:webp`, `:bmp`, or `:unknown`).
* `:stop` — adds `:width` and `:height` on success, or `:error` (reason) on failure.

Per-render encode timing (Kitty / Sixel / iTerm2 payload generation) is rolled into the existing `[:ex_ratatui, :render, :frame]` span — they happen inside the same NIF render pass.

## `:fit` and `:crop` do not upscale — this is intentional

This is the single most common point of confusion, so it gets its own section.

Both `:fit` and `:crop` clamp output to the **source image's natural pixel size**. They never upscale. If you give a 400×300 picsum photo to a render area sized 800×500 target pixels:

| Mode | Render output | Visible result |
|---|---|---|
| `:fit` | 400×300 | Image at natural size, anchored top-left, ~50% empty area |
| `:crop` | 400×300 | Identical to `:fit` here — both clamp to source dimensions |
| `:scale` | ~640×480 (aspect-preserving fill) | Image fills the area |

The difference between `:fit` and `:crop` only manifests when the **source is *larger* than the target** on at least one axis: `:fit` shrinks to fit (whole image visible, letterboxed); `:crop` keeps natural size and shows a window into the source corner.

This is upstream ratatui-image behavior in `Resize::needs_resize_pixels`, not something we layer on. We expose `ExRatatui.Image.render_size/4` so you can predict what each mode will do for a given combination of source dims, cell area, and font size — useful for status panels, layout decisions, or just understanding what you're seeing. The `examples/image_demo.exs` example uses it to surface the render output dimensions live as you cycle modes.

If you want "fill the area regardless of source size," use `:scale`. That's the only mode that upscales.

## Known limitations (v1)

* **No animated GIFs.** First frame only. Frame-by-frame animation needs render-loop integration that isn't here yet.
* **No SVG.** The underlying `image` crate doesn't include an SVG decoder.
* **No streaming / progressive decode.** Bytes are decoded all at once at `new/2`.
