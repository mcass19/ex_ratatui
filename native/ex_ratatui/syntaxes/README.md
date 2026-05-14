# Bundled Sublime syntaxes

Syntect ships a useful default `SyntaxSet`, but the BEAM languages we care about most aren't in it. This directory holds the `.sublime-syntax` files we vendor on top — each one is `include_str!`'d into the NIF binary and added to syntect's set at process startup by `native/ex_ratatui/src/widgets/highlighter.rs`. There's no runtime filesystem access; the files exist here purely so the source is inspectable and the licenses are easy to audit.

Today the list is short:

| File | Source | License |
|---|---|---|
| `Elixir.sublime-syntax` | [elixir-editors/elixir-sublime-syntax](https://github.com/elixir-editors/elixir-sublime-syntax) | MIT (see `LICENSE` in this directory) |

Erlang already rides along inside syntect's defaults. EEx, HEEx, and Surface don't, but the same path extends to them whenever there's a reason to pull them in.

## Adding a new language

Drop the `.sublime-syntax` file alongside this README and copy its LICENSE in beside it — we only vendor permissive licenses (MIT, Apache 2.0, and friends). Then teach the highlighter about it: an `include_str!` constant and a `builder.add(...)` call inside `syntaxes()` in `widgets/highlighter.rs`. Finally, add the language to `ExRatatui.CodeBlock`'s moduledoc, the cheatsheet, and the table above so users can actually discover it.
