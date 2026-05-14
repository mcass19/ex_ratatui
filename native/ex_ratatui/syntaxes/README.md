# Bundled Sublime syntaxes

This directory holds `.sublime-syntax` files we embed in the NIF binary
to extend syntect's default `SyntaxSet` with languages it doesn't bundle.

Each file is loaded by `widgets/highlighter.rs::syntaxes()` at process
startup via `SyntaxSet::load_defaults_newlines().into_builder()` →
`SyntaxDefinition::load_from_str(include_str!("…"), true, None)` → `.add()` →
`.build()`. Files are baked into the binary at compile time; no runtime
filesystem access.

## Contents

| File | Source | License |
|---|---|---|
| `Elixir.sublime-syntax` | [elixir-editors/elixir-sublime-syntax](https://github.com/elixir-editors/elixir-sublime-syntax) | MIT (see `LICENSE` in this directory) |

## Adding a new language

1. Drop the `.sublime-syntax` file here (verify the license is
   permissive — MIT / Apache 2.0 / similar — and copy the LICENSE
   alongside).
2. Add a `include_str!` + `builder.add(...)` line to `syntaxes()` in
   `native/ex_ratatui/src/widgets/highlighter.rs`.
3. Update `ExRatatui.CodeBlock`'s moduledoc "Supported languages"
   list and the cheatsheet's language note.
4. Add a row to the table above.
